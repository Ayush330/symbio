package commitments

import (
	"encoding/json"
	"errors"
	"net/http"
	"strings"

	"github.com/Ayush330/symbio/backend/internal/auth"
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
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	initiatorID, err := extractUserID(r)
	if err != nil {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	var req RequestCommitmentReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request payload", http.StatusBadRequest)
		return
	}

	commitment, err := h.Service.RequestCommitment(r.Context(), initiatorID, req)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(commitment)
}

func (h *Handler) AcceptCommitment(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	userID, err := extractUserID(r)
	if err != nil {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	// E.g., /commitments/uuid/accept -> parsing out of simplicity
	parts := strings.Split(r.URL.Path, "/")
	if len(parts) < 4 {
		http.Error(w, "Invalid path", http.StatusBadRequest)
		return
	}
	commID := parts[2]

	req := AcceptCommitmentReq{CommitmentID: commID}
	if _, err := h.Service.AcceptCommitment(r.Context(), userID, req); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusOK)
	w.Write([]byte(`{"status":"accepted"}`))
}

func (h *Handler) DenyCommitment(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	userID, err := extractUserID(r)
	if err != nil {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	parts := strings.Split(r.URL.Path, "/")
	if len(parts) < 4 {
		http.Error(w, "Invalid path", http.StatusBadRequest)
		return
	}
	commID := parts[2]

	req := DenyCommitmentReq{CommitmentID: commID}
	if _, err := h.Service.DenyCommitment(r.Context(), userID, req); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusOK)
	w.Write([]byte(`{"status":"denied"}`))
}
