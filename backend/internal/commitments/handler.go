package commitments

import (
	"encoding/json"
	"net/http"
	"strings"

	"github.com/Ayush330/symbio/backend/internal/auth"
	"github.com/Ayush330/symbio/backend/internal/transport"
)

type Handler struct {
	Service Service
}

func NewHandler(s Service) *Handler {
	return &Handler{Service: s}
}

func (h *Handler) RequestCommitment(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		transport.SendError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}

	initiatorID, err := auth.ExtractUserID(r)
	if err != nil {
		transport.SendError(w, http.StatusUnauthorized, "Unauthorized")
		return
	}

	var req RequestCommitmentReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		transport.SendError(w, http.StatusBadRequest, "Invalid request body")
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

	// Extract commitment ID from path: /commitments/{id}/accept
	parts := strings.Split(strings.TrimPrefix(r.URL.Path, "/commitments/"), "/")
	if len(parts) < 2 || parts[1] != "accept" {
		transport.SendError(w, http.StatusBadRequest, "Invalid path")
		return
	}
	id := parts[0]

	userID, err := auth.ExtractUserID(r)
	if err != nil {
		transport.SendError(w, http.StatusUnauthorized, "Unauthorized")
		return
	}

	req := AcceptCommitmentReq{CommitmentID: id}
	commitment, err := h.Service.AcceptCommitment(r.Context(), userID, req)
	if err != nil {
		transport.SendError(w, http.StatusInternalServerError, err.Error())
		return
	}

	transport.WriteJSON(w, http.StatusOK, commitment)
}

func (h *Handler) DenyCommitment(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		transport.SendError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}

	// Extract commitment ID from path: /commitments/{id}/deny
	parts := strings.Split(strings.TrimPrefix(r.URL.Path, "/commitments/"), "/")
	if len(parts) < 2 || parts[1] != "deny" {
		transport.SendError(w, http.StatusBadRequest, "Invalid path")
		return
	}
	id := parts[0]

	userID, err := auth.ExtractUserID(r)
	if err != nil {
		transport.SendError(w, http.StatusUnauthorized, "Unauthorized")
		return
	}

	req := DenyCommitmentReq{CommitmentID: id}
	commitment, err := h.Service.DenyCommitment(r.Context(), userID, req)
	if err != nil {
		transport.SendError(w, http.StatusInternalServerError, err.Error())
		return
	}

	transport.WriteJSON(w, http.StatusOK, commitment)
}

func (h *Handler) CreateFavour(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		transport.SendError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}

	initiatorID, err := auth.ExtractUserID(r)
	if err != nil {
		transport.SendError(w, http.StatusUnauthorized, "Unauthorized")
		return
	}

	var req RequestCommitmentReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		transport.SendError(w, http.StatusBadRequest, "Invalid request body")
		return
	}

	favour, err := h.Service.CreateFavour(r.Context(), initiatorID, req)
	if err != nil {
		transport.SendError(w, http.StatusInternalServerError, err.Error())
		return
	}

	transport.WriteJSON(w, http.StatusCreated, favour)
}

func (h *Handler) ClassifyFavour(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		transport.SendError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}

	var req struct {
		Text string `json:"text"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		transport.SendError(w, http.StatusBadRequest, "Invalid request body")
		return
	}

	category, points := ClassifyFavour(req.Text)
	transport.WriteJSON(w, http.StatusOK, map[string]interface{}{
		"category": category,
		"points":   points,
	})
}

func (h *Handler) GetFavourConfig(w http.ResponseWriter, r *http.Request) {
	config := h.Service.GetFavourConfig()
	transport.WriteJSON(w, http.StatusOK, config)
}
