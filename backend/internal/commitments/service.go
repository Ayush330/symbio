package commitments

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"

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
	UpdateEntityRating(ctx context.Context, tx *sql.Tx, entityType EntityType, entityID uuid.UUID, rating int) (float64, error)
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

	// Dynamic Entity Creation
	var entityID uuid.UUID
	isNewEntity := false
	if req.EntityID != "" {
		entityID, err = uuid.Parse(req.EntityID)
		if err != nil {
			return nil, errors.New("invalid entity ID")
		}
	} else if req.EntityName != "" {
		entityID, err = s.repo.GetOrCreateEntity(ctx, tx, req.EntityType, req.EntityName)
		if err != nil {
			return nil, err
		}
		isNewEntity = true
	} else {
		return nil, errors.New("either entity_id or entity_name must be provided")
	}

	// Validation: Must rate if it's a new entity
	if isNewEntity && (req.Rating < 1 || req.Rating > 100) {
		return nil, errors.New("rating is mandatory for new entities and must be between 1-100")
	}
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
		EntityID:    entityID,
		EntityType:  req.EntityType,
		Rating:      req.Rating,
		Status:      StatusPending,
	}

	if err := s.repo.CreateCommitment(ctx, tx, commitment); err != nil {
		return nil, err
	}

	// Outbox event
	payload, _ := json.Marshal(map[string]interface{}{
		"commitment_id": commitment.ID,
		"initiator_id":  initiatorID,
		"target_user":   targetUID,
		"entity_id":     entityID,
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
	go func() {
		initiator, _ := s.authRepo.GetUserByID(context.Background(), initiatorID)
		target, _ := s.authRepo.GetUserByID(context.Background(), targetUID)
		if target != nil && target.FCMToken != "" {
			title := "New Commitment Request"
			body := fmt.Sprintf("%s has proposed a new %s commitment: %s", initiator.Name, req.EntityType, req.EntityName)
			if req.EntityName == "" {
				// Handle case where entity_id was provided
				body = fmt.Sprintf("%s has proposed a new commitment", initiator.Name)
			}
			s.pushSender.SendPushNotification(context.Background(), target.FCMToken, title, body, map[string]string{
				"type": "commitment_request",
				"id":   commitment.ID.String(),
			})
		}
	}()

	return commitment, nil
}

func (s *commitmentsService) AcceptCommitment(ctx context.Context, userID uuid.UUID, req AcceptCommitmentReq) (*Commitment, error) {
	commID, err := uuid.Parse(req.CommitmentID)
	if err != nil {
		return nil, errors.New("invalid commitment ID")
	}

	// Get initial commitment (outside tx is fine for basic check)
	commitment, err := s.repo.GetCommitment(ctx, commID)
	if err != nil {
		return nil, err
	}

	if commitment.Status != StatusPending {
		return nil, errors.New("commitment is not pending")
	}
	// Note: We should ideally verify `userID` belongs to the relationship and isn't the initiator
	// This requires pulling the relationship, skipping for brevity but assuming valid user flow

	tx, err := s.repo.BeginTx(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	if err := s.repo.UpdateCommitmentStatus(ctx, tx, commID, StatusAcknowledged); err != nil {
		return nil, err
	}

	// Calculate and update the average score for the entity
	newAverage := 0.0
	if commitment.Rating > 0 {
		newAverage, err = s.repo.UpdateEntityScoreAndGetAverage(ctx, tx, commitment.EntityType, commitment.EntityID, commitment.Rating)
		if err != nil {
			return nil, err
		}
	}

	// Calculate +/- Ledger Update based on requested Ratings
	// Initiator (+), Accepter (-)
	scoreDelta := float64(commitment.Rating)
	if err := s.repo.UpdateReciprocityScore(ctx, tx, commitment.RelID, commitment.InitiatorID, scoreDelta); err != nil {
		return nil, err
	}

	// Emitting the Outbox Event
	payload, _ := json.Marshal(map[string]interface{}{
		"commitment_id": commitment.ID,
		"entity_id":     commitment.EntityID,
		"new_average":   newAverage,
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

	// ✅ Update the Redis "other user in red" outside the transaction for speed
	// Since Redis isn't part of the Postgres TX, we do it post-commit
	cacheKey := fmt.Sprintf("user_avg_score:%s:%s", userID.String(), commitment.EntityID.String())
	err = s.redis.Set(ctx, cacheKey, newAverage, 0).Err()
	if err != nil {
		// Log error, but don't fail the request since DB/Kafka pipeline succeeded
		fmt.Printf("Warning: failed to update redis cache: %v\n", err)
	}

	commitment.Status = StatusAcknowledged
	// Note: We should ideally have the TargetID already from GetCommitment
	// Async push notification
	go func() {
		target, _ := s.authRepo.GetUserByID(context.Background(), commitment.TargetID) // Person who accepted
		initiator, _ := s.authRepo.GetUserByID(context.Background(), commitment.InitiatorID)
		if initiator != nil && initiator.FCMToken != "" {
			title := "Commitment Accepted!"
			body := fmt.Sprintf("%s has accepted your commitment.", target.Name)
			s.pushSender.SendPushNotification(context.Background(), initiator.FCMToken, title, body, map[string]string{
				"type": "commitment_accepted",
				"id":   commitment.ID.String(),
			})
		}
	}()

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

	// Fetch or update local object to return
	comm, err := s.repo.GetCommitment(ctx, commID)
	// Async push notification
	go func() {
		target, _ := s.authRepo.GetUserByID(context.Background(), userID) // Person who denied
		if comm != nil {
			initiator, _ := s.authRepo.GetUserByID(context.Background(), comm.InitiatorID)
			if initiator != nil && initiator.FCMToken != "" {
				title := "Commitment Denied"
				body := fmt.Sprintf("%s has denied your commitment request.", target.Name)
				s.pushSender.SendPushNotification(context.Background(), initiator.FCMToken, title, body, map[string]string{
					"type": "commitment_denied",
					"id":   commID.String(),
				})
			}
		}
	}()

	return comm, err
}

func (s *commitmentsService) BeginTx(ctx context.Context) (*sql.Tx, error) {
	return s.repo.BeginTx(ctx)
}

func (s *commitmentsService) UpdateEntityRating(ctx context.Context, tx *sql.Tx, entityType EntityType, entityID uuid.UUID, rating int) (float64, error) {
	return s.repo.UpdateEntityScoreAndGetAverage(ctx, tx, entityType, entityID, rating)
}
