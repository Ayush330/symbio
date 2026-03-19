package main

import (
	"bufio"
	"database/sql"
	"errors"
	"net"
	"net/http"
	"os"
	"time"

	"github.com/Ayush330/symbio/backend/internal/auth"
	"github.com/Ayush330/symbio/backend/internal/commitments"
	"github.com/Ayush330/symbio/backend/internal/db"
	"github.com/Ayush330/symbio/backend/internal/logger"
	"github.com/Ayush330/symbio/backend/internal/notifications"
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
	// 0. Initialize Logger
	isProd := os.Getenv("APP_ENV") == "production"
	logger.Init(isProd)
	defer logger.Log.Sync()

	logger.Info("Initializing Sybmio Services", "env", os.Getenv("APP_ENV"))

	// 1. Initialize DBs
	postgresDB, err := db.NewPostgresDB()
	if err != nil {
		logger.Fatal("Failed to initialize database", "error", err)
	}
	defer postgresDB.Close()

	// 1.5 Auto-migrate missing columns
	ensureSchema(postgresDB)

	redisClient, err := db.NewRedisClient()
	if err != nil {
		logger.Fatal("Failed to initialize redis", "error", err)
	}
	defer redisClient.Close()

	// 2. Initialize Auth setup
	authRepo := auth.NewRepository(postgresDB)
	authService := auth.NewService(authRepo, redisClient)
	authHandler := auth.NewHandler(authService)

	// 3. Initialize Notifications / FCM setup
	fcmService, fcmErr := notifications.NewFCMService("firebase-adminsdk.json")
	if fcmErr != nil {
		logger.Warn("FCM service not initialized", "error", fcmErr)
	}

	// 4. Initialize WebSocket setup first for Broadcaster
	wsManager := ws.NewManager()
	go wsManager.Run()
	broadcaster := &wsBroadcaster{m: wsManager}

	// 6. Initialize Notifications Handler (FCM only now)
	notificationsHandler := notifications.NewHandler(authRepo)

	// 6.5 Setup Classifier
	keywordClassifier := &commitments.KeywordClassifier{}
	geminiApiKey := os.Getenv("GEMINI_API_KEY")
	classifier := commitments.Classifier(keywordClassifier)
	if geminiApiKey != "" {
		classifier = &commitments.GeminiClassifier{
			ApiKey:   geminiApiKey,
			Fallback: keywordClassifier,
		}
	}

	// 5. Initialize Commitments setup
	commRepo := commitments.NewRepository(postgresDB)
	commService := commitments.NewService(commRepo, redisClient, authRepo, fcmService, broadcaster, classifier)
	commitmentsHandler := commitments.NewHandler(commService)

	wsHandler := ws.NewHandler(wsManager, commService)

	// 7. (Kafka & Outbox removed)

	// 8. Setup Routing
	mux := http.NewServeMux()

	mux.HandleFunc("/signup", authHandler.Signup)
	mux.HandleFunc("/login", authHandler.Login)
	mux.HandleFunc("/forgot-password", authHandler.ForgotPassword)
	mux.HandleFunc("/reset-password", authHandler.ResetPassword)
	mux.HandleFunc("/user/fcm-token", authHandler.UpdateFCMToken)
	mux.HandleFunc("/ws", wsHandler.ServeWS)

	// Friends & Social
	friendsHandler := auth.NewFriendsHandler(postgresDB, authService, fcmService, broadcaster)
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
	mux.HandleFunc("/commitments/", commitmentsHandler.AcceptCommitment) // Handles /commitments/{id}/accept and /deny

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
	logger.Info("Starting server", "port", port)

	handler := recoveryMiddleware(loggingMiddleware(corsMiddleware(mux)))

	if err := http.ListenAndServe(port, handler); err != nil {
		logger.Fatal("Could not start server", "error", err)
	}
}

func ensureSchema(db *sql.DB) {
	logger.Info("Checking database schema")

	// Ensure essential columns exist
	_, _ = db.Exec(`ALTER TABLE commitments ADD COLUMN IF NOT EXISTS category VARCHAR(20)`)
	_, _ = db.Exec(`ALTER TABLE commitments ADD COLUMN IF NOT EXISTS points INT DEFAULT 0`)
	_, _ = db.Exec(`ALTER TABLE commitments ADD COLUMN IF NOT EXISTS text TEXT`)
	_, _ = db.Exec(`ALTER TABLE commitments ADD COLUMN IF NOT EXISTS rating INT DEFAULT 0`)
	
	// New rich metadata columns
	_, _ = db.Exec(`ALTER TABLE commitments ADD COLUMN IF NOT EXISTS effort INT DEFAULT 0`)
	_, _ = db.Exec(`ALTER TABLE commitments ADD COLUMN IF NOT EXISTS time_taken INT DEFAULT 0`)
	_, _ = db.Exec(`ALTER TABLE commitments ADD COLUMN IF NOT EXISTS sacrifice INT DEFAULT 0`)
	_, _ = db.Exec(`ALTER TABLE commitments ADD COLUMN IF NOT EXISTS urgency INT DEFAULT 0`)
	_, _ = db.Exec(`ALTER TABLE commitments ADD COLUMN IF NOT EXISTS intensity FLOAT DEFAULT 0`)
	_, _ = db.Exec(`ALTER TABLE commitments ADD COLUMN IF NOT EXISTS explanation TEXT`)

	// Relax constraints to support pure text/points flow
	_, _ = db.Exec(`ALTER TABLE commitments ALTER COLUMN entity_id DROP NOT NULL`)
	_, _ = db.Exec(`ALTER TABLE commitments ALTER COLUMN entity_type DROP NOT NULL`)
	// Ensure phone is a unique identifier
	_, _ = db.Exec(`CREATE UNIQUE INDEX IF NOT EXISTS idx_users_phone ON users(phone) WHERE phone IS NOT NULL AND phone != ''`)

	logger.Info("Schema check complete")
}

func recoveryMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if err := recover(); err != nil {
				logger.Error("PANIC RECOVERED", "error", err, "path", r.URL.Path)
				http.Error(w, "Internal server error", http.StatusInternalServerError)
			}
		}()
		next.ServeHTTP(w, r)
	})
}

func loggingMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		
		// Create a custom response writer to capture status code
		ww := &responseWriter{ResponseWriter: w, status: http.StatusOK}
		
		next.ServeHTTP(ww, r)
		
		logger.Info("Request handled",
			"method", r.Method,
			"path", r.URL.Path,
			"status", ww.status,
			"duration", time.Since(start).String(),
			"remote_addr", r.RemoteAddr,
		)
	})
}

type responseWriter struct {
	http.ResponseWriter
	status int
}

func (rw *responseWriter) WriteHeader(code int) {
	rw.status = code
	rw.ResponseWriter.WriteHeader(code)
}

func (rw *responseWriter) Flush() {
	if fl, ok := rw.ResponseWriter.(http.Flusher); ok {
		fl.Flush()
	}
}

func (rw *responseWriter) Hijack() (net.Conn, *bufio.ReadWriter, error) {
	if hj, ok := rw.ResponseWriter.(http.Hijacker); ok {
		return hj.Hijack()
	}
	return nil, nil, errors.New("webserver doesn't support hijacking")
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
