package auth

import (
	"context"
	"errors"
	"fmt"
	"net/smtp"
	"os"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
	"golang.org/x/crypto/bcrypt"
)

var (
	ErrInvalidCredentials = errors.New("invalid email or password")
)

type Service interface {
	Signup(ctx context.Context, req SignupRequest) (*User, string, error)
	Login(ctx context.Context, req LoginRequest) (*User, string, error)
	ForgotPassword(ctx context.Context, req ForgotPasswordRequest) error
	ResetPassword(ctx context.Context, req ResetPasswordRequest) error
	SaveFCMToken(ctx context.Context, userID uuid.UUID, token string) error
}

type authService struct {
	repo  Repository
	redis *redis.Client
}

func NewService(repo Repository, redis *redis.Client) Service {
	return &authService{repo: repo, redis: redis}
}

func (s *authService) Signup(ctx context.Context, req SignupRequest) (*User, string, error) {
	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		return nil, "", err
	}

	user := &User{
		Email:      req.Email,
		PasswdHash: string(hashedPassword),
		Name:       req.Name,
		Phone:      req.Phone,
	}

	err = s.repo.CreateUser(ctx, user)
	if err != nil {
		return nil, "", err
	}

	token, err := GenerateJWT(user.ID.String())
	if err != nil {
		return nil, "", err
	}

	return user, token, nil
}

func (s *authService) SaveFCMToken(ctx context.Context, userID uuid.UUID, token string) error {
	return s.repo.SaveFCMToken(ctx, userID, token)
}

func (s *authService) Login(ctx context.Context, req LoginRequest) (*User, string, error) {
	user, err := s.repo.GetUserByEmail(ctx, req.Email)
	if err != nil {
		if err == ErrUserNotFound {
			return nil, "", ErrInvalidCredentials
		}
		return nil, "", err
	}

	err = bcrypt.CompareHashAndPassword([]byte(user.PasswdHash), []byte(req.Password))
	if err != nil {
		return nil, "", ErrInvalidCredentials
	}

	token, err := GenerateJWT(user.ID.String())
	if err != nil {
		return nil, "", err
	}

	return user, token, nil
}

func GenerateJWT(userID string) (string, error) {
	jwtSecret := os.Getenv("JWT_SECRET")
	if jwtSecret == "" {
		jwtSecret = "supersecretdefaultkey_change_in_prod"
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"sub": userID,
		"exp": time.Now().Add(time.Hour * 72).Unix(),
		"iat": time.Now().Unix(),
	})

	return token.SignedString([]byte(jwtSecret))
}

func ParseJWT(tokenString string) (jwt.MapClaims, error) {
	jwtSecret := os.Getenv("JWT_SECRET")
	if jwtSecret == "" {
		jwtSecret = "supersecretdefaultkey_change_in_prod"
	}

	token, err := jwt.Parse(tokenString, func(t *jwt.Token) (interface{}, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, errors.New("unexpected signing method")
		}
		return []byte(jwtSecret), nil
	})

	if err != nil {
		return nil, err
	}

	if claims, ok := token.Claims.(jwt.MapClaims); ok && token.Valid {
		return claims, nil
	}

	return nil, errors.New("invalid token")
}

func (s *authService) ForgotPassword(ctx context.Context, req ForgotPasswordRequest) error {
	user, err := s.repo.GetUserByEmail(ctx, req.Email)
	if err != nil {
		if err == ErrUserNotFound {
			// Don't leak user existence for security, but we'll log it for dev
			fmt.Printf("Forgot password requested for non-existent email: %s\n", req.Email)
			return nil
		}
		return err
	}

	token := uuid.New().String()
	key := fmt.Sprintf("reset_token:%s", token)

	// Store token for 15 minutes
	err = s.redis.Set(ctx, key, user.ID.String(), 15*time.Minute).Err()
	if err != nil {
		return err
	}

	smtpHost := os.Getenv("SMTP_HOST")
	smtpPort := os.Getenv("SMTP_PORT")
	smtpUser := os.Getenv("SMTP_USER")
	smtpPass := os.Getenv("SMTP_PASS")

	frontendURL := os.Getenv("FRONTEND_URL")
	if frontendURL == "" {
		frontendURL = "http://localhost:8080"
	}

	resetLink := fmt.Sprintf("%s/reset-password?token=%s", frontendURL, token)

	// Send real email if SMTP is configured
	if smtpHost != "" && smtpUser != "" && smtpPass != "" {
		if smtpPort == "" {
			smtpPort = "587"
		}
		
		auth := smtp.PlainAuth("", smtpUser, smtpPass, smtpHost)
		from := smtpUser
		to := []string{user.Email}

		subject := "Subject: Symbio - Reset Your Password\r\n"
		body := fmt.Sprintf("Hi %s,\r\n\r\nYou requested a password reset for Symbio.\r\nClick the link below to securely reset your password:\r\n\r\n%s\r\n\r\nThis link will expire in 15 minutes.\r\n", 
			user.Name, resetLink)

		msg := []byte(subject + "\r\n" + body)

		err := smtp.SendMail(smtpHost+":"+smtpPort, auth, from, to, msg)
		if err != nil {
			fmt.Printf("Failed to send reset email to %s: %v\n", user.Email, err)
		} else {
			fmt.Printf("Reset email successfully sent to %s\n", user.Email)
		}
	} else {
		// Fallback: In local dev without SMTP, just log it
		fmt.Printf("\n--- PASSWORD RESET REQUEST ---\n")
		fmt.Printf("User: %s (ID: %s)\n", user.Email, user.ID)
		fmt.Printf("Token: %s\n", token)
		fmt.Printf("Link: %s\n", resetLink)
		fmt.Printf("------------------------------\n\n")
	}

	return nil
}

func (s *authService) ResetPassword(ctx context.Context, req ResetPasswordRequest) error {
	key := fmt.Sprintf("reset_token:%s", req.Token)
	userIDStr, err := s.redis.Get(ctx, key).Result()
	if err != nil {
		return errors.New("invalid or expired reset token")
	}

	userID, err := uuid.Parse(userIDStr)
	if err != nil {
		return err
	}

	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(req.NewPassword), bcrypt.DefaultCost)
	if err != nil {
		return err
	}

	err = s.repo.UpdatePassword(ctx, userID, string(hashedPassword))
	if err != nil {
		return err
	}

	// Delete token after successful use
	s.redis.Del(ctx, key)

	return nil
}
