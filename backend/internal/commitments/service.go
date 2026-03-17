package commitments

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"log"

	"github.com/Ayush330/symbio/backend/internal/auth"
	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
)

type PushSender interface {
	SendPushNotification(ctx context.Context, token, title, body string, data map[string]string) error
}

type Service interface {
	RequestCommitment(ctx context.Context, initiatorID uuid.UUID, req RequestCommitmentReq) (*Commitment, error)
	AcceptCommitment(ctx context.Context, userID uuid.UUID, req AcceptCommitmentReq) (*Commitment, error)
	DenyCommitment(ctx context.Context, userID uuid.UUID, req DenyCommitmentReq) (*Commitment, error)
	BeginTx(ctx context.Context) (*sql.Tx, error)
	CreateFavour(ctx context.Context, initiatorID uuid.UUID, req RequestCommitmentReq) (*Commitment, error)
	GetFavourConfig() map[string]int
}

type commitmentsService struct {
	repo       Repository
	redis      *redis.Client
	authRepo   auth.Repository
	pushSender PushSender
}

func NewService(repo Repository, redisClient *redis.Client, authRepo auth.Repository, pushSender PushSender) Service {
	return &commitmentsService{
		repo:       repo,
		redis:      redisClient,
		authRepo:   authRepo,
		pushSender: pushSender,
	}
}

func (s *commitmentsService) RequestCommitment(ctx context.Context, initiatorID uuid.UUID, req RequestCommitmentReq) (*Commitment, error) {
	targetUID, err := uuid.Parse(req.TargetUserID)
	if err != nil {
		return nil, errors.New("invalid target user ID")
	}

	tx, err := s.repo.BeginTx(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	// Validation: Rating must be valid if provided
	if req.Rating != 0 && (req.Rating < 1 || req.Rating > 100) {
		return nil, errors.New("rating must be between 1 and 100")
	}

	relID, err := s.repo.GetActiveRelationship(ctx, tx, initiatorID, targetUID)
	if err != nil {
		return nil, fmt.Errorf("cannot create commitment: %v", err)
	}

	commitment := &Commitment{
		RelID:       relID,
		InitiatorID: initiatorID,
		TargetID:    targetUID,
		Rating:      req.Rating,
		Status:      StatusPending,
		Text:        req.Text,
	}

	if req.Text != "" {
		cat, pts := ClassifyFavour(req.Text)
		commitment.Category = cat
		commitment.Points = pts
	}

	if err := s.repo.CreateCommitment(ctx, tx, commitment); err != nil {
		return nil, err
	}

	// Outbox event
	payload, _ := json.Marshal(map[string]interface{}{
		"commitment_id": commitment.ID,
		"initiator_id":  initiatorID,
		"target_user":   targetUID,
		"status":        commitment.Status,
	})

	outboxEvent := &OutboxEvent{
		AggregateType: "Commitment",
		AggregateID:   commitment.ID,
		EventType:     "CommitmentRequested",
		Payload:       string(payload),
	}

	if err := s.repo.InsertOutboxEvent(ctx, tx, outboxEvent); err != nil {
		return nil, err
	}

	if err := tx.Commit(); err != nil {
		return nil, err
	}

	// Async push notification
	if s.pushSender != nil {
		go func() {
			initiator, err := s.authRepo.GetUserByID(context.Background(), initiatorID)
			if err != nil {
				log.Printf("Warning: failed to fetch initiator (%s) for request notification: %v", initiatorID, err)
				return
			}
			target, err := s.authRepo.GetUserByID(context.Background(), targetUID)
			if err != nil {
				log.Printf("Warning: failed to fetch target (%s) for request notification: %v", targetUID, err)
				return
			}

			if target != nil && target.FCMToken != "" {
				title := "New Commitment Request"
				body := fmt.Sprintf("%s has proposed a new commitment: %s", initiator.Name, req.Text)
				
				err := s.pushSender.SendPushNotification(context.Background(), target.FCMToken, title, body, map[string]string{
					"type":  "commitment_request",
					"id":    commitment.ID.String(),
					"color": "#800080",
					"icon":  "notification_icon_heart",
				})
				if err != nil {
					log.Printf("Error sending request notification to %s: %v", target.Email, err)
				} else {
					log.Printf("Successfully sent request notification to %s", target.Email)
				}
			}
		}()
	}

	return commitment, nil
}

func (s *commitmentsService) AcceptCommitment(ctx context.Context, userID uuid.UUID, req AcceptCommitmentReq) (*Commitment, error) {
	commID, err := uuid.Parse(req.CommitmentID)
	if err != nil {
		return nil, errors.New("invalid commitment ID")
	}

	// Get initial commitment
	commitment, err := s.repo.GetCommitment(ctx, commID)
	if err != nil {
		return nil, err
	}

	if commitment.Status != StatusPending {
		return nil, errors.New("commitment is not pending")
	}

	tx, err := s.repo.BeginTx(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	if err := s.repo.UpdateCommitmentStatus(ctx, tx, commID, StatusAcknowledged); err != nil {
		return nil, err
	}

	// Calculate +/- Ledger Update based on requested Ratings or Points
	scoreDelta := float64(commitment.Rating)
	if commitment.Points > 0 {
		scoreDelta = float64(commitment.Points)
	}
	if err := s.repo.UpdateReciprocityScore(ctx, tx, commitment.RelID, commitment.InitiatorID, scoreDelta); err != nil {
		return nil, err
	}

	// Emitting the Outbox Event
	payload, _ := json.Marshal(map[string]interface{}{
		"commitment_id": commitment.ID,
		"status":        StatusAcknowledged,
	})

	outboxEvent := &OutboxEvent{
		AggregateType: "Commitment",
		AggregateID:   commitment.ID,
		EventType:     "CommitmentAccepted",
		Payload:       string(payload),
	}

	if err := s.repo.InsertOutboxEvent(ctx, tx, outboxEvent); err != nil {
		return nil, err
	}

	if err := tx.Commit(); err != nil {
		return nil, err
	}

	commitment.Status = StatusAcknowledged

	// Async push notification
	if s.pushSender != nil {
		go func() {
			target, err := s.authRepo.GetUserByID(context.Background(), commitment.TargetID)
			if err != nil {
				log.Printf("Warning: failed to fetch target for accept notification: %v", err)
				return
			}
			initiator, err := s.authRepo.GetUserByID(context.Background(), commitment.InitiatorID)
			if err != nil {
				log.Printf("Warning: failed to fetch initiator for accept notification: %v", err)
				return
			}
			if initiator != nil && initiator.FCMToken != "" {
				title := "Commitment Accepted!"
				body := fmt.Sprintf("%s has accepted your commitment.", target.Name)
				err := s.pushSender.SendPushNotification(context.Background(), initiator.FCMToken, title, body, map[string]string{
					"type":  "commitment_accepted",
					"id":    commitment.ID.String(),
					"color": "#800080",
					"icon":  "notification_icon_heart",
				})
				if err != nil {
					log.Printf("Error sending accept notification to %s: %v", initiator.Email, err)
				}
			}
		}()
	}

	return commitment, nil
}

func (s *commitmentsService) DenyCommitment(ctx context.Context, userID uuid.UUID, req DenyCommitmentReq) (*Commitment, error) {
	commID, err := uuid.Parse(req.CommitmentID)
	if err != nil {
		return nil, errors.New("invalid commitment ID")
	}

	tx, err := s.repo.BeginTx(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	if err := s.repo.UpdateCommitmentStatus(ctx, tx, commID, StatusDenied); err != nil {
		return nil, err
	}

	payload, _ := json.Marshal(map[string]interface{}{
		"commitment_id": commID,
		"status":        StatusDenied,
	})

	outboxEvent := &OutboxEvent{
		AggregateType: "Commitment",
		AggregateID:   commID,
		EventType:     "CommitmentDenied",
		Payload:       string(payload),
	}

	if err := s.repo.InsertOutboxEvent(ctx, tx, outboxEvent); err != nil {
		return nil, err
	}

	if err := tx.Commit(); err != nil {
		return nil, err
	}

	comm, err := s.repo.GetCommitment(ctx, commID)
	if s.pushSender != nil {
		go func() {
			target, err := s.authRepo.GetUserByID(context.Background(), userID)
			if err != nil {
				log.Printf("Warning: failed to fetch target for deny notification: %v", err)
				return
			}
			if comm != nil {
				initiator, err := s.authRepo.GetUserByID(context.Background(), comm.InitiatorID)
				if err != nil {
					log.Printf("Warning: failed to fetch initiator for deny notification: %v", err)
					return
				}
				if initiator != nil && initiator.FCMToken != "" {
					title := "Commitment Denied"
					body := fmt.Sprintf("%s has denied your commitment request.", target.Name)
					err := s.pushSender.SendPushNotification(context.Background(), initiator.FCMToken, title, body, map[string]string{
						"type":  "commitment_denied",
						"id":    commID.String(),
						"color": "#800080",
						"icon":  "notification_icon_heart",
					})
					if err != nil {
						log.Printf("Error sending deny notification to %s: %v", initiator.Email, err)
					}
				}
			}
		}()
	}

	return comm, err
}

func (s *commitmentsService) CreateFavour(ctx context.Context, initiatorID uuid.UUID, req RequestCommitmentReq) (*Commitment, error) {
	targetUID, err := uuid.Parse(req.TargetUserID)
	if err != nil {
		return nil, errors.New("invalid target user ID")
	}

	tx, err := s.repo.BeginTx(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	relID, err := s.repo.GetActiveRelationship(ctx, tx, initiatorID, targetUID)
	if err != nil {
		return nil, fmt.Errorf("cannot create favour: %v", err)
	}

	cat, pts := ClassifyFavour(req.Text)

	commitment := &Commitment{
		RelID:       relID,
		InitiatorID: initiatorID,
		TargetID:    targetUID,
		Text:        req.Text,
		Category:    cat,
		Points:      pts,
		Status:      StatusAcknowledged, // Favours are instant
	}

	if err := s.repo.CreateCommitment(ctx, tx, commitment); err != nil {
		return nil, err
	}

	if err := s.repo.UpdateReciprocityScore(ctx, tx, relID, initiatorID, float64(pts)); err != nil {
		log.Printf("Error updating reciprocity score for favour: %v", err)
		return nil, err
	}

	payload, _ := json.Marshal(map[string]interface{}{
		"favour_id":     commitment.ID,
		"from_user_id":  initiatorID,
		"to_user_id":    targetUID,
		"category":      cat,
		"points":        pts,
		"text":          req.Text,
		"status":        StatusAcknowledged,
	})

	outboxEvent := &OutboxEvent{
		AggregateType: "Favour",
		AggregateID:   commitment.ID,
		EventType:     "FAVOUR_CREATED",
		Payload:       string(payload),
	}

	if err := s.repo.InsertOutboxEvent(ctx, tx, outboxEvent); err != nil {
		return nil, err
	}

	if err := tx.Commit(); err != nil {
		return nil, err
	}

	if s.pushSender != nil {
		go func() {
			log.Printf("DEBUG: Starting push notification flow for favour %s", commitment.ID)
			initiator, err := s.authRepo.GetUserByID(context.Background(), initiatorID)
			if err != nil {
				log.Printf("Warning: failed to fetch initiator (%s) for favour notification: %v", initiatorID, err)
				return
			}
			target, err := s.authRepo.GetUserByID(context.Background(), targetUID)
			if err != nil {
				log.Printf("Warning: failed to fetch target (%s) for favour notification: %v", targetUID, err)
				return
			}

			if target != nil && target.FCMToken != "" {
				log.Printf("DEBUG: Found FCM token for target %s: %s", target.Email, target.FCMToken)
				title := "New Favour Received!"
				body := fmt.Sprintf("%s said: %s", initiator.Name, req.Text)
				err := s.pushSender.SendPushNotification(context.Background(), target.FCMToken, title, body, map[string]string{
					"type":  "favour_created",
					"id":    commitment.ID.String(),
					"color": "#800080",
					"icon":  "notification_icon_heart",
				})
				if err != nil {
					log.Printf("Error sending favour notification to %s: %v", target.Email, err)
				} else {
					log.Printf("Successfully sent favour notification to %s", target.Email)
				}
			} else {
				log.Printf("Warning: Target user %s has no FCM token or target is nil.", targetUID)
			}
		}()
	}

	return commitment, nil
}

func (s *commitmentsService) BeginTx(ctx context.Context) (*sql.Tx, error) {
	return s.repo.BeginTx(ctx)
}

func (s *commitmentsService) GetFavourConfig() map[string]int {
	return map[string]int{
		"HEALTH":    50,
		"MONEY":     40,
		"HELP":      30,
		"EMOTIONAL": 20,
		"OTHER":     10,
	}
}
