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

func (w *wsBroadcaster) Broadcast(message []byte) {
	w.m.Broadcast <- message
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

	// 4. Initialize Commitments setup (needed by WS)
	commRepo := commitments.NewRepository(postgresDB)
	commService := commitments.NewService(commRepo, redisClient, authRepo, fcmService)
	commitmentsHandler := commitments.NewHandler(commService)

	// 4. Initialize WebSocket setup
	wsManager := ws.NewManager()
	go wsManager.Run()
	wsHandler := ws.NewHandler(wsManager, commService)

	// 6. Initialize Notifications / Twilio setup
	twilioService, twilioErr := notifications.NewTwilioService()
	if twilioErr != nil {
		log.Printf("Warning: Twilio service not initialized: %v", twilioErr)
	}
	notificationsHandler := notifications.NewHandler(twilioService, authRepo)

	// 6. Initialize Outbox Relay & Kafka
	kafkaProducer := kafka.NewProducer()
	defer kafkaProducer.Close()
	outboxRelay := outbox.NewRelay(postgresDB, kafkaProducer, 5*time.Second)
	go outboxRelay.Start(context.Background())

	// 6. Setup Routing
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
	mux.HandleFunc("/friends/", friendsHandler.GetFriendActivity) // /friends/{id}/activity
	mux.HandleFunc("/user/lookup", friendsHandler.LookupUser)

	// Entities autocomplete & creation
	// Wrapper to pass the websocket manager to the entity handler
	wsWrapper := &wsBroadcaster{m: wsManager}

	entitiesHandler := commitments.NewEntitiesHandler(postgresDB, wsWrapper)
	mux.HandleFunc("/entities", func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodPost {
			entitiesHandler.CreateEntity(w, r)
		} else {
			entitiesHandler.ListEntities(w, r)
		}
	})

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

	// 5. Start Server
	port := ":8080"
	log.Printf("Starting server on port %s", port)

	// Wrap mux with Recovery and CORS
	handler := recoveryMiddleware(corsMiddleware(mux))

	if err := http.ListenAndServe(port, handler); err != nil {
		log.Fatalf("Could not start server: %v\n", err)
	}
}

func ensureSchema(db *sql.DB) {
	log.Println("Checking database schema...")
	
	// Add category column if missing
	_, err := db.Exec(`ALTER TABLE commitments ADD COLUMN IF NOT EXISTS category VARCHAR(20)`)
	if err != nil {
		log.Printf("Warning: failed to add category column: %v", err)
	}

	// Add points column if missing
	_, err = db.Exec(`ALTER TABLE commitments ADD COLUMN IF NOT EXISTS points INT DEFAULT 0`)
	if err != nil {
		log.Printf("Warning: failed to add points column: %v", err)
	}

	// Add text column if missing
	log.Println("Ensuring 'text' column exists in commitments...")
	_, err = db.Exec(`ALTER TABLE commitments ADD COLUMN IF NOT EXISTS text TEXT`)
	if err != nil {
		log.Fatalf("CRITICAL: failed to add text column: %v", err)
	}

	// Drop NOT NULL constraints on entity_id and entity_type since flavours make them optional
	log.Println("Relaxing NOT NULL constraints for flavours...")
	_, err = db.Exec(`ALTER TABLE commitments ALTER COLUMN entity_id DROP NOT NULL`)
	if err != nil {
		log.Printf("Warning: failed to drop not-null on entity_id: %v", err)
	}
	_, err = db.Exec(`ALTER TABLE commitments ALTER COLUMN entity_type DROP NOT NULL`)
	if err != nil {
		log.Printf("Warning: failed to drop not-null on entity_type: %v", err)
	}

	// Drop rating check constraint since flavours have 0 rating (violates 1-100 check)
	_, err = db.Exec(`ALTER TABLE commitments DROP CONSTRAINT IF EXISTS commitments_rating_check`)
	if err != nil {
		log.Printf("Warning: failed to drop rating check constraint: %v", err)
	}

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
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")

		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusOK)
			return
		}

		next.ServeHTTP(w, r)
	})
}
