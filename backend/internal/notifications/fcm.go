package notifications

import (
	"context"
	"fmt"
	"log"

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
	if token == "" {
		return nil // No token, skip
	}

	message := &messaging.Message{
		Notification: &messaging.Notification{
			Title: title,
			Body:  body,
		},
		Data:  data,
		Token: token,
	}

	_, err := s.client.Send(ctx, message)
	if err != nil {
		log.Printf("Failed to send FCM message to %s: %v", token, err)
		return err
	}

	return nil
}
