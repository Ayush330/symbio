package notifications

import (
	"context"
	"fmt"
	"github.com/Ayush330/symbio/backend/internal/logger"

	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/messaging"
	"google.golang.org/api/option"
)

type FCMService struct {
	client *messaging.Client
}

func NewFCMService(credentialsPath string) (*FCMService, error) {
	opt := option.WithCredentialsFile(credentialsPath)
	app, err := firebase.NewApp(context.Background(), nil, opt)
	if err != nil {
		return nil, fmt.Errorf("error initializing firebase app: %v", err)
	}

	client, err := app.Messaging(context.Background())
	if err != nil {
		return nil, fmt.Errorf("error getting messaging client: %v", err)
	}

	return &FCMService{client: client}, nil
}

func (s *FCMService) SendPushNotification(ctx context.Context, token, title, body string, data map[string]string) error {
	if s == nil || s.client == nil {
		logger.Warn("FCM: Attempted to send but service/client is nil", "token", token)
		return nil 
	}
	if token == "" {
		logger.Warn("FCM: Attempted to send but token is empty")
		return nil 
	}

	// Prepare data map for general consumption (don't delete color/icon, just copy them)
	if data == nil {
		data = make(map[string]string)
	}
	color := data["color"]
	icon := data["icon"]

	message := &messaging.Message{
		Notification: &messaging.Notification{
			Title: title,
			Body:  body,
		},
		Data: data,
		Android: &messaging.AndroidConfig{
			Priority: "high", // Critical for real-time visibility
			Notification: &messaging.AndroidNotification{
				Color:    "#EEFF41", // Bright Light Green
				Icon:     icon,
				Sound:    "default",
				Priority: messaging.PriorityHigh,
			},
		},
		APNS: &messaging.APNSConfig{
			Headers: map[string]string{
				"apns-priority": "10",
			},
			Payload: &messaging.APNSPayload{
				Aps: &messaging.Aps{
					Alert: &messaging.ApsAlert{
						Title: title,
						Body:  body,
					},
					Badge: pointerInt(1),
					Sound: "default",
				},
			},
		},
		Token: token,
	}

	logger.Info("FCM: Sending message", "token", token, "title", title, "color", color, "icon", icon)
	msgID, err := s.client.Send(ctx, message)
	if err != nil {
		logger.Error("FCM: FAILED to send", "token", token, "error", err)
		return err
	}

	logger.Info("FCM: Successfully sent message", "token", token, "msgID", msgID)
	return nil
}

func pointerInt(i int) *int {
	return &i
}
