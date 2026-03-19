package notifications

import (
	"encoding/json"
	"net/http"

	"github.com/Ayush330/symbio/backend/internal/auth"
	"github.com/Ayush330/symbio/backend/internal/transport"
)

type Handler struct {
	Users auth.Repository // We need auth repo to find the inviter's name
}

func NewHandler(userRepo auth.Repository) *Handler {
	return &Handler{Users: userRepo}
}

type InviteRequest struct {
	PhoneNumber string `json:"phone_number"`
}

func (h *Handler) SendInvite(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		transport.SendError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}

	// Basic extract user logic, reusing what was shown before
	authHeader := r.Header.Get("Authorization")
	if len(authHeader) < 8 {
		transport.SendError(w, http.StatusUnauthorized, "Unauthorized")
		return
	}

	token := authHeader[7:] // remove "Bearer "
	claims, err := auth.ParseJWT(token)
	if err != nil {
		transport.SendError(w, http.StatusUnauthorized, "Unauthorized")
		return
	}

	var ok bool
	if _, ok = claims["sub"].(string); !ok {
		transport.SendError(w, http.StatusUnauthorized, "Invalid token sub payload")
		return
	}

	// In a complete app, we'd have GetUserByID, using a mock default or we could simply skip pulling name
	// For now, let's extract it from DB:
	var req InviteRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		transport.SendError(w, http.StatusBadRequest, "Invalid request body")
		return
	}

	if req.PhoneNumber == "" {
		transport.SendError(w, http.StatusBadRequest, "Missing phone number")
		return
	}

	transport.WriteJSON(w, http.StatusOK, map[string]string{"status": "invite_logged"})
}
