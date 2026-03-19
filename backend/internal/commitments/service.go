package commitments

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"github.com/Ayush330/symbio/backend/internal/logger"

	"github.com/Ayush330/symbio/backend/internal/auth"
	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
)

type PushSender interface {
	SendPushNotification(ctx context.Context, token, title, body string, data map[string]string) error
}

type Broadcaster interface {
	BroadcastToUser(userID string, payload []byte)
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
	repo        Repository
	redis       *redis.Client
	authRepo    auth.Repository
	pushSender  PushSender
	broadcaster Broadcaster
	classifier  Classifier
}

func NewService(repo Repository, redisClient *redis.Client, authRepo auth.Repository, pushSender PushSender, broadcaster Broadcaster, classifier Classifier) Service {
	return &commitmentsService{
		repo:        repo,
		redis:       redisClient,
		authRepo:    authRepo,
		pushSender:  pushSender,
		broadcaster: broadcaster,
		classifier:  classifier,
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

	metrics, err := s.classifier.Analyze(ctx, req.Text)
	if err != nil {
		logger.Warn("Classification failed", "text", req.Text, "error", err)
		// Minimal fallback
		metrics = &KarmaMetrics{FinalScore: 1, CategoryWeight: 10}
	}

	cat := string(req.Category)
	if cat == "" {
		// Reverse mapping or direct check if cat is already correct in Analyze?
		// For now we'll assume Gemini/Fallback provides it.
	}

	commitment := &Commitment{
		RelID:       relID,
		InitiatorID: initiatorID,
		TargetID:    targetUID,
		Rating:      req.Rating,
		Status:      StatusPending,
		Text:        req.Text,
		Category:    req.Category, // Use provided if exists
		Points:      req.Points,
		Effort:      metrics.Effort,
		TimeTaken:   metrics.Time,
		Sacrifice:   metrics.Sacrifice,
		Urgency:     metrics.Urgency,
		Intensity:   metrics.Intensity100,
		Explanation: metrics.Explanation,
	}

	// Manual metric overrides
	if req.Effort > 0 { commitment.Effort = req.Effort }
	if req.TimeTaken > 0 { commitment.TimeTaken = req.TimeTaken }
	if req.Sacrifice > 0 { commitment.Sacrifice = req.Sacrifice }
	if req.Urgency > 0 { commitment.Urgency = req.Urgency }
	if req.Intensity > 0 { commitment.Intensity = req.Intensity }

	// Double check category and points from analysis if not provided
	if commitment.Category == "" {
		// Category detection logic normally in classifier
	}
	if commitment.Points == 0 {
		commitment.Points = metrics.FinalScore
	}

	if err := s.repo.CreateCommitment(ctx, tx, commitment); err != nil {
		return nil, err
	}

	if err := tx.Commit(); err != nil {
		return nil, err
	}

	// Real-time broadcast
	if s.broadcaster != nil {
		logger.Debug("SYNC: Broadcasting commitment_requested", "target", targetUID)
		commBytes, _ := json.Marshal(commitment)
		wsMsg, _ := json.Marshal(map[string]interface{}{
			"type": "commitment_requested",
			"data": json.RawMessage(commBytes),
		})
		s.broadcaster.BroadcastToUser(targetUID.String(), wsMsg)

		// Signal a refresh for both users
		logger.Debug("SYNC: Sending data_refresh", "target", targetUID, "initiator", initiatorID)
		refreshMsg, _ := json.Marshal(map[string]interface{}{
			"type": "data_refresh",
			"data": map[string]string{"reason": "commitment_requested"},
		})
		s.broadcaster.BroadcastToUser(targetUID.String(), refreshMsg)
		s.broadcaster.BroadcastToUser(initiatorID.String(), refreshMsg)
	}

	// Async push notification
	if s.pushSender != nil {
		go func() {
			initiator, err := s.authRepo.GetUserByID(context.Background(), initiatorID)
			if err != nil {
				logger.Warn("Failed to fetch initiator for request notification", "userID", initiatorID, "error", err)
				return
			}
			target, err := s.authRepo.GetUserByID(context.Background(), targetUID)
			if err != nil {
				logger.Warn("Failed to fetch target for request notification", "userID", targetUID, "error", err)
				return
			}

			if target != nil && target.FCMToken != "" {
				title := "New Commitment Request"
				body := fmt.Sprintf("%s has proposed a new commitment: %s", initiator.Name, req.Text)

				err := s.pushSender.SendPushNotification(context.Background(), target.FCMToken, title, body, map[string]string{
					"type":  "commitment_request",
					"id":    commitment.ID.String(),
					"color": "#90EE90",
					"icon":  "notification_icon_heart",
				})
				if err != nil {
					logger.Error("Error sending request notification", "email", target.Email, "error", err)
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

	if err := tx.Commit(); err != nil {
		return nil, err
	}

	commitment.Status = StatusAcknowledged

	// Real-time broadcast
	if s.broadcaster != nil {
		logger.Debug("SYNC: Broadcasting commitment_accepted", "initiator", commitment.InitiatorID, "target", commitment.TargetID)
		commBytes, _ := json.Marshal(commitment)
		wsMsg, _ := json.Marshal(map[string]interface{}{
			"type": "commitment_accepted",
			"data": json.RawMessage(commBytes),
		})
		s.broadcaster.BroadcastToUser(commitment.InitiatorID.String(), wsMsg)
		s.broadcaster.BroadcastToUser(commitment.TargetID.String(), wsMsg)

		logger.Debug("SYNC: Sending data_refresh", "initiator", commitment.InitiatorID, "target", commitment.TargetID)
		refreshMsg, _ := json.Marshal(map[string]interface{}{
			"type": "data_refresh",
			"data": map[string]string{"commitment_id": commitment.ID.String(), "status": string(commitment.Status)},
		})
		s.broadcaster.BroadcastToUser(commitment.InitiatorID.String(), refreshMsg)
		s.broadcaster.BroadcastToUser(commitment.TargetID.String(), refreshMsg)
	}

	// Async push notification
	if s.pushSender != nil {
		go func() {
			target, err := s.authRepo.GetUserByID(context.Background(), commitment.TargetID)
			if err != nil {
				logger.Warn("Failed to fetch target for accept notification", "error", err)
				return
			}
			initiator, err := s.authRepo.GetUserByID(context.Background(), commitment.InitiatorID)
			if err != nil {
				logger.Warn("Failed to fetch initiator for accept notification", "error", err)
				return
			}
			if initiator != nil && initiator.FCMToken != "" {
				title := "Commitment Accepted!"
				body := fmt.Sprintf("%s has accepted your commitment.", target.Name)
				err := s.pushSender.SendPushNotification(context.Background(), initiator.FCMToken, title, body, map[string]string{
					"type":  "commitment_accepted",
					"id":    commitment.ID.String(),
					"color": "#90EE90",
					"icon":  "notification_icon_heart",
				})
				if err != nil {
					logger.Error("Error sending accept notification", "email", initiator.Email, "error", err)
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

	if err := tx.Commit(); err != nil {
		return nil, err
	}

	comm, err := s.repo.GetCommitment(ctx, commID)

	// Real-time broadcast
	if s.broadcaster != nil && comm != nil {
		logger.Debug("SYNC: Broadcasting commitment_denied", "initiator", comm.InitiatorID)
		commBytes, _ := json.Marshal(comm)
		wsMsg, _ := json.Marshal(map[string]interface{}{
			"type": "commitment_denied",
			"data": json.RawMessage(commBytes),
		})
		s.broadcaster.BroadcastToUser(comm.InitiatorID.String(), wsMsg)

		logger.Debug("SYNC: Sending data_refresh", "initiator", comm.InitiatorID, "target", comm.TargetID)
		refreshMsg, _ := json.Marshal(map[string]interface{}{
			"type": "data_refresh",
			"data": map[string]string{"commitment_id": comm.ID.String(), "status": string(comm.Status)},
		})
		s.broadcaster.BroadcastToUser(comm.InitiatorID.String(), refreshMsg)
		s.broadcaster.BroadcastToUser(comm.TargetID.String(), refreshMsg)
	}

	if s.pushSender != nil {
		go func() {
			target, err := s.authRepo.GetUserByID(context.Background(), userID)
			if err != nil {
				logger.Warn("Failed to fetch target for deny notification", "error", err)
				return
			}
			if comm != nil {
				initiator, err := s.authRepo.GetUserByID(context.Background(), comm.InitiatorID)
				if err != nil {
					logger.Warn("Failed to fetch initiator for deny notification", "error", err)
					return
				}
				if initiator != nil && initiator.FCMToken != "" {
					title := "Commitment Denied"
					body := fmt.Sprintf("%s has denied your commitment request.", target.Name)
					err := s.pushSender.SendPushNotification(context.Background(), initiator.FCMToken, title, body, map[string]string{
						"type":  "commitment_denied",
						"id":    commID.String(),
						"color": "#90EE90",
						"icon":  "notification_icon_heart",
					})
					if err != nil {
						logger.Error("Error sending deny notification", "email", initiator.Email, "error", err)
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

	metrics, err := s.classifier.Analyze(ctx, req.Text)
	if err != nil {
		metrics = &KarmaMetrics{FinalScore: 10}
	}

	commitment := &Commitment{
		RelID:       relID,
		InitiatorID: initiatorID,
		TargetID:    targetUID,
		Text:        req.Text,
		Category:    req.Category,
		Points:      req.Points,
		Rating:      req.Points, // Ensure rating check (1-100) is satisfied
		Effort:      metrics.Effort,
		TimeTaken:   metrics.Time,
		Sacrifice:   metrics.Sacrifice,
		Urgency:     metrics.Urgency,
		Intensity:   metrics.Intensity100,
		Explanation: metrics.Explanation,
		Status:      StatusAcknowledged,
	}

	if commitment.Rating < 1 {
		commitment.Rating = 10 // Default to 10 to satisfy check constraint
	}

	// Manual metric overrides
	if req.Effort > 0 { commitment.Effort = req.Effort }
	if req.TimeTaken > 0 { commitment.TimeTaken = req.TimeTaken }
	if req.Sacrifice > 0 { commitment.Sacrifice = req.Sacrifice }
	if req.Urgency > 0 { commitment.Urgency = req.Urgency }
	if req.Intensity > 0 { commitment.Intensity = req.Intensity }

	if commitment.Points == 0 {
		commitment.Points = metrics.FinalScore
	}

	if err := s.repo.CreateCommitment(ctx, tx, commitment); err != nil {
		return nil, err
	}

	if err := s.repo.UpdateReciprocityScore(ctx, tx, relID, initiatorID, float64(commitment.Points)); err != nil {
		logger.Error("Error updating reciprocity score for favour", "error", err)
		return nil, err
	}

	if err := tx.Commit(); err != nil {
		return nil, err
	}

	// Real-time broadcast
	if s.broadcaster != nil {
		logger.Debug("SYNC: Broadcasting favour_created", "target", targetUID, "initiator", initiatorID)
		commBytes, _ := json.Marshal(commitment)
		wsMsg, _ := json.Marshal(map[string]interface{}{
			"type": "favour_created",
			"data": json.RawMessage(commBytes),
		})
		s.broadcaster.BroadcastToUser(targetUID.String(), wsMsg)
		s.broadcaster.BroadcastToUser(initiatorID.String(), wsMsg)

		// Signal refresh for both users
		logger.Debug("SYNC: Sending data_refresh (favour)", "target", targetUID, "initiator", initiatorID)
		refreshMsg, _ := json.Marshal(map[string]interface{}{
			"type": "data_refresh",
			"data": map[string]string{"reason": "favour_created"},
		})
		s.broadcaster.BroadcastToUser(targetUID.String(), refreshMsg)
		s.broadcaster.BroadcastToUser(initiatorID.String(), refreshMsg)
	}

	if s.pushSender != nil {
		go func() {
			initiator, err := s.authRepo.GetUserByID(context.Background(), initiatorID)
			if err != nil {
				logger.Warn("Failed to fetch initiator for favour notification", "userID", initiatorID, "error", err)
				return
			}
			target, err := s.authRepo.GetUserByID(context.Background(), targetUID)
			if err != nil {
				logger.Warn("Failed to fetch target for favour notification", "userID", targetUID, "error", err)
				return
			}

			if target != nil && target.FCMToken != "" {
				title := "New Favour Received!"
				body := fmt.Sprintf("%s said: %s", initiator.Name, req.Text)
				err := s.pushSender.SendPushNotification(context.Background(), target.FCMToken, title, body, map[string]string{
					"type":  "favour_created",
					"id":    commitment.ID.String(),
					"color": "#90EE90",
					"icon":  "notification_icon_heart",
				})
				if err != nil {
					logger.Error("Error sending favour notification", "email", target.Email, "error", err)
				}
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
