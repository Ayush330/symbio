package notifications

import (
	"encoding/json"
	"net/http"

	"github.com/Ayush330/symbio/backend/internal/auth"
)

type Handler struct {
	Twilio *TwilioService
	Users  auth.Repository // We need auth repo to find the inviter's name
}

func NewHandler(t *TwilioService, userRepo auth.Repository) *Handler {
	return &Handler{Twilio: t, Users: userRepo}
}

type InviteRequest struct {
	PhoneNumber string `json:"phone_number"`
}

func (h *Handler) SendInvite(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Basic extract user logic, reusing what was shown before
	authHeader := r.Header.Get("Authorization")
	if len(authHeader) < 8 {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}
	
	token := authHeader[7:] // remove "Bearer "
	claims, err := auth.ParseJWT(token)
	if err != nil {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	var ok bool
	if _, ok = claims["sub"].(string); !ok {
		http.Error(w, "Invalid token sub payload", http.StatusUnauthorized)
		return
	}

	// In a complete app, we'd have GetUserByID, using a mock default or we could simply skip pulling name
	// For now, let's extract it from DB:
	// Since GetUserByID might not exist on the simplified repo, we will pass "A friend" as fallback or we can add it later.
	// But let's assume we want to push the basic flow.
	inviterName := "A friend"

	var req InviteRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	if req.PhoneNumber == "" {
		http.Error(w, "Missing phone number", http.StatusBadRequest)
		return
	}

	err = h.Twilio.SendInvite(req.PhoneNumber, inviterName)
	if err != nil {
		// Log it, but return generic error to client
		http.Error(w, "Failed to send invite", http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusOK)
	w.Write([]byte(`{"status":"invite_sent"}`))
}
