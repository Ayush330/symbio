package main

import (
	"context"
	"database/sql"
	"log"
	"net/http"
	"time"

	"github.com/Ayush330/symbio/backend/internal/auth"
	"github.com/Ayush330/symbio/backend/internal/commitments"
	"github.com/Ayush330/symbio/backend/internal/db"
	"github.com/Ayush330/symbio/backend/internal/kafka"
	"github.com/Ayush330/symbio/backend/internal/notifications"
	"github.com/Ayush330/symbio/backend/internal/outbox"
	"github.com/Ayush330/symbio/backend/internal/ws"
)

// wsBroadcaster implements the commitments.Broadcaster interface
type wsBroadcaster struct {
	m *ws.Manager
}

func (w *wsBroadcaster) BroadcastToUser(userID string, payload []byte) {
	w.m.Message <- ws.Envelope{
		TargetID: userID,
		Payload:  payload,
	}
}

func main() {
	// 1. Initialize DBs
	postgresDB, err := db.NewPostgresDB()
	if err != nil {
		log.Fatalf("Failed to initialize database: %v", err)
	}
	defer postgresDB.Close()

	// 1.5 Auto-migrate missing columns
	ensureSchema(postgresDB)

	redisClient, err := db.NewRedisClient()
	if err != nil {
		log.Fatalf("Failed to initialize redis: %v", err)
	}
	defer redisClient.Close()

	// 2. Initialize Auth setup
	authRepo := auth.NewRepository(postgresDB)
	authService := auth.NewService(authRepo, redisClient)
	authHandler := auth.NewHandler(authService)

	// 3. Initialize Notifications / FCM setup
	fcmService, fcmErr := notifications.NewFCMService("firebase-adminsdk.json")
	if fcmErr != nil {
		log.Printf("Warning: FCM service not initialized: %v", fcmErr)
	}

	// 4. Initialize WebSocket setup first for Broadcaster
	wsManager := ws.NewManager()
	go wsManager.Run()
	broadcaster := &wsBroadcaster{m: wsManager}

	// 5. Initialize Commitments setup
	commRepo := commitments.NewRepository(postgresDB)
	commService := commitments.NewService(commRepo, redisClient, authRepo, fcmService, broadcaster)
	commitmentsHandler := commitments.NewHandler(commService)

	wsHandler := ws.NewHandler(wsManager, commService)

	// 6. Initialize Notifications / Twilio setup
	twilioService, twilioErr := notifications.NewTwilioService()
	if twilioErr != nil {
		log.Printf("Warning: Twilio service not initialized: %v", twilioErr)
	}
	notificationsHandler := notifications.NewHandler(twilioService, authRepo)

	// 7. Initialize Outbox Relay & Kafka
	kafkaProducer := kafka.NewProducer()
	defer kafkaProducer.Close()
	outboxRelay := outbox.NewRelay(postgresDB, kafkaProducer, 5*time.Second)
	go outboxRelay.Start(context.Background())

	// 8. Setup Routing
	mux := http.NewServeMux()

	mux.HandleFunc("/signup", authHandler.Signup)
	mux.HandleFunc("/login", authHandler.Login)
	mux.HandleFunc("/forgot-password", authHandler.ForgotPassword)
	mux.HandleFunc("/reset-password", authHandler.ResetPassword)
	mux.HandleFunc("/user/fcm-token", authHandler.UpdateFCMToken)
	mux.HandleFunc("/ws", wsHandler.ServeWS)

	// Friends & Social
	friendsHandler := auth.NewFriendsHandler(postgresDB, authService, fcmService)
	mux.HandleFunc("/friends", friendsHandler.ListFriends)
	mux.HandleFunc("/friends/requests", friendsHandler.ListFriendRequests)
	mux.HandleFunc("/friends/request", friendsHandler.SendFriendRequest)
	mux.HandleFunc("/friends/accept", friendsHandler.AcceptFriendRequest)
	mux.HandleFunc("/friends/reject", friendsHandler.RejectFriendRequest)
	mux.HandleFunc("/friends/invite", friendsHandler.SendInvite)
	mux.HandleFunc("/friends/", friendsHandler.GetFriendActivity) // /friends/{id}/activity
	mux.HandleFunc("/activity", friendsHandler.GetGlobalActivity) // Global activity tab
	mux.HandleFunc("/user/lookup", friendsHandler.LookupUser)

	mux.HandleFunc("/favour/create", commitmentsHandler.CreateFavour)
	mux.HandleFunc("/favour/config", commitmentsHandler.GetFavourConfig)
	mux.HandleFunc("/favour/classify", commitmentsHandler.ClassifyFavour)

	// Stats & Graph
	mux.HandleFunc("/relationship/", friendsHandler.GetRelationshipStats)
	mux.HandleFunc("/profile/stats", friendsHandler.GetProfileStats)
	mux.HandleFunc("/activity/graph", friendsHandler.GetActivityGraph)

	// Notifications
	mux.HandleFunc("/invites", notificationsHandler.SendInvite)

	// Add a simple healthcheck route
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("OK"))
	})

	// 9. Start Server
	port := ":8080"
	log.Printf("Starting server on port %s", port)

	handler := recoveryMiddleware(corsMiddleware(mux))

	if err := http.ListenAndServe(port, handler); err != nil {
		log.Fatalf("Could not start server: %v\n", err)
	}
}

func ensureSchema(db *sql.DB) {
	log.Println("Checking database schema...")
	
	// Ensure essential columns exist
	_, _ = db.Exec(`ALTER TABLE commitments ADD COLUMN IF NOT EXISTS category VARCHAR(20)`)
	_, _ = db.Exec(`ALTER TABLE commitments ADD COLUMN IF NOT EXISTS points INT DEFAULT 0`)
	_, _ = db.Exec(`ALTER TABLE commitments ADD COLUMN IF NOT EXISTS text TEXT`)
	_, _ = db.Exec(`ALTER TABLE commitments ADD COLUMN IF NOT EXISTS rating INT DEFAULT 0`)

	// Relax constraints to support pure text/points flow
	_, _ = db.Exec(`ALTER TABLE commitments ALTER COLUMN entity_id DROP NOT NULL`)
	_, _ = db.Exec(`ALTER TABLE commitments ALTER COLUMN entity_type DROP NOT NULL`)
	// Ensure phone is a unique identifier
	_, _ = db.Exec(`CREATE UNIQUE INDEX IF NOT EXISTS idx_users_phone ON users(phone) WHERE phone IS NOT NULL AND phone != ''`)

	log.Println("Schema check complete.")
}

func recoveryMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if err := recover(); err != nil {
				log.Printf("PANIC RECOVERED: %v", err)
				http.Error(w, "Internal server error", http.StatusInternalServerError)
			}
		}()
		next.ServeHTTP(w, r)
	})
}

func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type")

		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusOK)
			return
		}

		next.ServeHTTP(w, r)
	})
}
