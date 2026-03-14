package auth

import (
	"time"

	"github.com/google/uuid"
)

type User struct {
	ID         uuid.UUID `json:"id"`
	Email      string    `json:"email"`
	PasswdHash string    `json:"-"`
	Name       string    `json:"name"`
	Phone      string    `json:"phone"`
	Gender     string    `json:"gender"`
	FCMToken   string    `json:"fcm_token,omitempty"`
	CreatedAt  time.Time `json:"created_at"`
}

type SignupRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
	Name     string `json:"name"`
	Phone    string `json:"phone"`
	Gender   string `json:"gender"`
}

type LoginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

type AuthResponse struct {
	Token string `json:"token"`
	User  User   `json:"user"`
}

type ForgotPasswordRequest struct {
	Email string `json:"email"`
}

type ResetPasswordRequest struct {
	Token       string `json:"token"`
	NewPassword string `json:"password"`
}

type UpdateFCMTokenRequest struct {
	Token string `json:"token"`
}
