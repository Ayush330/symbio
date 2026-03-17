package notifications

import (
	"errors"
	"fmt"
	"os"

	"github.com/twilio/twilio-go"
	twilioApi "github.com/twilio/twilio-go/rest/api/v2010"
)

type TwilioService struct {
	client       *twilio.RestClient
	fromNumber   string
}

func NewTwilioService() (*TwilioService, error) {
	// expects TWILIO_ACCOUNT_SID and TWILIO_AUTH_TOKEN in environment by default
	client := twilio.NewRestClient()
	
	from := os.Getenv("TWILIO_FROM_NUMBER")
	if from == "" {
		return nil, errors.New("missing TWILIO_FROM_NUMBER environment variable")
	}

	return &TwilioService{
		client:     client,
		fromNumber: from,
	}, nil
}

func (s *TwilioService) SendInvite(toNumber string, inviterName string) error {
	msg := fmt.Sprintf("Hey! %s has invited you to join Kizuna. Sign up here: https://kizuna.app", inviterName)
	
	params := &twilioApi.CreateMessageParams{}
	params.SetTo(toNumber)
	params.SetFrom(s.fromNumber)
	params.SetBody(msg)

	_, err := s.client.Api.CreateMessage(params)
	if err != nil {
		return fmt.Errorf("failed to send twilio SMS: %w", err)
	}

	return nil
}
