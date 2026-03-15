package commitments

import (
	"encoding/json"
	"errors"
	"net/http"
	"strings"

	"github.com/Ayush330/symbio/backend/internal/auth"
	"github.com/Ayush330/symbio/backend/internal/transport"
	"github.com/google/uuid"
)

type Handler struct {
	Service Service
}

func NewHandler(s Service) *Handler {
	return &Handler{Service: s}
}

// Utility to extract UserID from context/headers (In a real app, use a middleware)
func extractUserID(r *http.Request) (uuid.UUID, error) {
	authHeader := r.Header.Get("Authorization")
	if authHeader == "" {
		return uuid.Nil, errors.New("unauthorized")
	}
	parts := strings.Split(authHeader, " ")
	if len(parts) != 2 {
		return uuid.Nil, errors.New("unauthorized")
	}

	claims, err := auth.ParseJWT(parts[1])
	if err != nil {
		return uuid.Nil, err
	}

	sub, ok := claims["sub"].(string)
	if !ok {
		return uuid.Nil, errors.New("invalid token payload")
	}

	return uuid.Parse(sub)
}

func (h *Handler) RequestCommitment(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		transport.SendError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}

	initiatorID, err := extractUserID(r)
	if err != nil {
		transport.SendError(w, http.StatusUnauthorized, "Unauthorized")
		return
	}

	var req RequestCommitmentReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		transport.SendError(w, http.StatusBadRequest, "Invalid request payload")
		return
	}

	commitment, err := h.Service.RequestCommitment(r.Context(), initiatorID, req)
	if err != nil {
		transport.SendError(w, http.StatusInternalServerError, err.Error())
		return
	}

	transport.WriteJSON(w, http.StatusCreated, commitment)
}

func (h *Handler) AcceptCommitment(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		transport.SendError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}

	userID, err := extractUserID(r)
	if err != nil {
		transport.SendError(w, http.StatusUnauthorized, "Unauthorized")
		return
	}

	// E.g., /commitments/uuid/accept -> parsing out of simplicity
	parts := strings.Split(r.URL.Path, "/")
	if len(parts) < 4 {
		transport.SendError(w, http.StatusBadRequest, "Invalid path")
		return
	}
	commID := parts[2]

	req := AcceptCommitmentReq{CommitmentID: commID}
	if _, err := h.Service.AcceptCommitment(r.Context(), userID, req); err != nil {
		transport.SendError(w, http.StatusInternalServerError, err.Error())
		return
	}

	transport.WriteJSON(w, http.StatusOK, map[string]string{"status": "accepted"})
}

func (h *Handler) DenyCommitment(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		transport.SendError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}

	userID, err := extractUserID(r)
	if err != nil {
		transport.SendError(w, http.StatusUnauthorized, "Unauthorized")
		return
	}

	parts := strings.Split(r.URL.Path, "/")
	if len(parts) < 4 {
		transport.SendError(w, http.StatusBadRequest, "Invalid path")
		return
	}
	commID := parts[2]

	req := DenyCommitmentReq{CommitmentID: commID}
	if _, err := h.Service.DenyCommitment(r.Context(), userID, req); err != nil {
		transport.SendError(w, http.StatusInternalServerError, err.Error())
		return
	}

	transport.WriteJSON(w, http.StatusOK, map[string]string{"status": "denied"})
}
