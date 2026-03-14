package ws

import (
	"log"
	"net/http"
	"strings"

	"github.com/gorilla/websocket"
	"github.com/Ayush330/symbio/backend/internal/auth"
	"github.com/Ayush330/symbio/backend/internal/commitments"
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	// Allowing all origins for development
	CheckOrigin: func(r *http.Request) bool {
		return true
	},
}

type Handler struct {
	Manager            *Manager
	CommitmentsService commitments.Service
}

func NewHandler(m *Manager, c commitments.Service) *Handler {
	return &Handler{
		Manager:            m,
		CommitmentsService: c,
	}
}

func (h *Handler) ServeWS(w http.ResponseWriter, r *http.Request) {
	// Authentication
	// Try parsing token from URL Query: ?token=...
	tokenString := r.URL.Query().Get("token")

	// If not in query, try Authorization header: Bearer ...
	if tokenString == "" {
		authHeader := r.Header.Get("Authorization")
		if authHeader != "" {
			parts := strings.Split(authHeader, " ")
			if len(parts) == 2 && parts[0] == "Bearer" {
				tokenString = parts[1]
			}
		}
	}

	if tokenString == "" {
		http.Error(w, "Unauthorized: missing token", http.StatusUnauthorized)
		return
	}

	claims, err := auth.ParseJWT(tokenString)
	if err != nil {
		log.Printf("WS auth error: %v", err)
		http.Error(w, "Unauthorized: invalid token", http.StatusUnauthorized)
		return
	}

	userID, ok := claims["sub"].(string)
	if !ok {
		http.Error(w, "Unauthorized: invalid token payload", http.StatusUnauthorized)
		return
	}

	// Upgrade HTTP to WS
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Println("Upgrade error:", err)
		return
	}

	client := &Client{
		Manager:            h.Manager,
		CommitmentsService: h.CommitmentsService,
		Conn:               conn,
		Send:               make(chan []byte, 256),
		UserID:             userID,
	}

	client.Manager.Register <- client

	// Start goroutines for reading and writing
	go client.WritePump()
	go client.ReadPump()
}
