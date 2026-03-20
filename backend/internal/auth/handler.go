package auth

import (
	"encoding/json"
	"errors"
	"net/http"
	"strings"

	"github.com/Ayush330/symbio/backend/internal/transport"
	"github.com/google/uuid"
)

type Handler struct {
	Service Service
}

func NewHandler(s Service) *Handler {
	return &Handler{Service: s}
}

// ExtractUserID extracts user ID from JWT token in Authorization header
func ExtractUserID(r *http.Request) (uuid.UUID, error) {
	authHeader := r.Header.Get("Authorization")
	if authHeader == "" {
		return uuid.Nil, ErrInvalidCredentials
	}

	tokenStr := strings.TrimPrefix(authHeader, "Bearer ")
	claims, err := ParseJWT(tokenStr)
	if err != nil {
		return uuid.Nil, err
	}

	sub, ok := claims["sub"].(string)
	if !ok {
		return uuid.Nil, errors.New("invalid token payload")
	}

	return uuid.Parse(sub)
}

func (h *Handler) Signup(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		transport.SendError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}

	var req SignupRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		transport.SendError(w, http.StatusBadRequest, "Invalid input data")
		return
	}

	// Validate mandatory fields
	if req.Email == "" || req.Password == "" || req.Name == "" || req.Phone == "" || req.Gender == "" {
		transport.SendError(w, http.StatusBadRequest, "All fields are mandatory: Email, Password, Name, Phone, Gender")
		return
	}

	user, token, err := h.Service.Signup(r.Context(), req)
	if err != nil {
		if err == ErrUserDuplicate {
			transport.SendError(w, http.StatusConflict, "Email already in use")
			return
		}
		transport.SendError(w, http.StatusInternalServerError, "Internal server error")
		return
	}

	resp := AuthResponse{
		Token: token,
		User:  *user,
	}

	transport.WriteJSON(w, http.StatusCreated, resp)
}

func (h *Handler) Login(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		transport.SendError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}

	var req LoginRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		transport.SendError(w, http.StatusBadRequest, "Invalid input data")
		return
	}

	user, token, err := h.Service.Login(r.Context(), req)
	if err != nil {
		if err == ErrInvalidCredentials {
			transport.SendError(w, http.StatusUnauthorized, "Invalid credentials")
			return
		}
		transport.SendError(w, http.StatusInternalServerError, "Internal server error")
		return
	}

	resp := AuthResponse{
		Token: token,
		User:  *user,
	}

	transport.WriteJSON(w, http.StatusOK, resp)
}

func (h *Handler) UpdateFCMToken(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		transport.SendError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}

	userID, err := ExtractUserID(r)
	if err != nil {
		transport.SendError(w, http.StatusUnauthorized, "Unauthorized")
		return
	}

	var req UpdateFCMTokenRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		transport.SendError(w, http.StatusBadRequest, "Invalid input data")
		return
	}

	if req.Token == "" {
		transport.SendError(w, http.StatusBadRequest, "Token is required")
		return
	}

	err = h.Service.SaveFCMToken(r.Context(), userID, req.Token)
	if err != nil {
		transport.SendError(w, http.StatusInternalServerError, "Internal server error")
		return
	}

	transport.WriteJSON(w, http.StatusOK, map[string]string{"message": "FCM token updated successfully"})
}

func (h *Handler) ForgotPassword(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		transport.SendError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}

	var req ForgotPasswordRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		transport.SendError(w, http.StatusBadRequest, "Invalid input data")
		return
	}

	if err := h.Service.ForgotPassword(r.Context(), req); err != nil {
		transport.SendError(w, http.StatusInternalServerError, "Internal server error")
		return
	}

	transport.WriteJSON(w, http.StatusOK, map[string]string{"message": "If that email is in our system, we've sent reset instructions."})
}

func (h *Handler) ResetPassword(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		transport.SendError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}

	var req ResetPasswordRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		transport.SendError(w, http.StatusBadRequest, "Invalid input data")
		return
	}

	if err := h.Service.ResetPassword(r.Context(), req); err != nil {
		transport.SendError(w, http.StatusBadRequest, err.Error())
		return
	}

	transport.WriteJSON(w, http.StatusOK, map[string]string{"message": "Password reset successful."})
}
