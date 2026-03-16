package commitments

import (
	"context"
	"database/sql"
	"fmt"
	"time"

	"github.com/google/uuid"
)

type EntityType string
type CommitmentStatus string

const (
	TypeMaterialistic EntityType = "MATERIAL"
	TypeEmotional     EntityType = "EMOTIONAL"

	StatusPending      CommitmentStatus = "PENDING"
	StatusAcknowledged CommitmentStatus = "ACKNOWLEDGED"
	StatusFlaked       CommitmentStatus = "FLAKED"
	StatusDenied       CommitmentStatus = "DENIED"
)

type Commitment struct {
	ID          uuid.UUID        `json:"id"`
	RelID       uuid.UUID        `json:"rel_id"`
	InitiatorID uuid.UUID        `json:"initiator_id"`
	TargetID    uuid.UUID        `json:"target_id"`
	EntityID    *uuid.UUID       `json:"entity_id,omitempty"`
	EntityType  EntityType       `json:"entity_type,omitempty"`
	Text        string           `json:"text,omitempty"`
	Category    string           `json:"category,omitempty"`
	Points      int              `json:"points"`
	Rating      int              `json:"rating"`
	Status      CommitmentStatus `json:"status"`
	CreatedAt   time.Time        `json:"created_at"`
}

type MaterialisticEntity struct {
	ID         uuid.UUID `json:"id"`
	Name       string    `json:"name"`
	TotalScore int64     `json:"total_score"`
	UsersVotes int       `json:"users_votes"`
}

type EmotionalEntity struct {
	ID         uuid.UUID `json:"id"`
	Name       string    `json:"name"`
	TotalScore int64     `json:"total_score"`
	UsersVotes int       `json:"users_votes"`
}

type OutboxEvent struct {
	ID            uuid.UUID `json:"id"`
	AggregateType string    `json:"aggregate_type"`
	AggregateID   uuid.UUID `json:"aggregate_id"`
	EventType     string    `json:"event_type"`
	Payload       string    `json:"payload"`
	CreatedAt     time.Time `json:"created_at"`
}

// Request payloads
type RequestCommitmentReq struct {
	TargetUserID string     `json:"target_user_id"`
	EntityID     string     `json:"entity_id,omitempty"`
	EntityName   string     `json:"entity_name,omitempty"` // Used if EntityID is empty
	EntityType   EntityType `json:"entity_type,omitempty"`
	Rating       int        `json:"rating,omitempty"` // 1-100
	Text         string     `json:"text,omitempty"`
}

type AcceptCommitmentReq struct {
	CommitmentID string `json:"commitment_id"`
}

type DenyCommitmentReq struct {
	CommitmentID string `json:"commitment_id"`
}

// Repository Interface
type Repository interface {
	BeginTx(ctx context.Context) (*sql.Tx, error)
	GetActiveRelationship(ctx context.Context, tx *sql.Tx, userA uuid.UUID, userB uuid.UUID) (uuid.UUID, error)
	CreateCommitment(ctx context.Context, tx *sql.Tx, c *Commitment) error
	GetCommitment(ctx context.Context, id uuid.UUID) (*Commitment, error)
	UpdateCommitmentStatus(ctx context.Context, tx *sql.Tx, id uuid.UUID, status CommitmentStatus) error
	UpdateEntityScoreAndGetAverage(ctx context.Context, tx *sql.Tx, entityType EntityType, entityID uuid.UUID, rating int) (float64, error)
	InsertOutboxEvent(ctx context.Context, tx *sql.Tx, event *OutboxEvent) error
	GetOrCreateEntity(ctx context.Context, tx *sql.Tx, entityType EntityType, name string) (uuid.UUID, error)
	GetRelationship(ctx context.Context, tx *sql.Tx, relID uuid.UUID) (uuid.UUID, uuid.UUID, error)
	UpdateReciprocityScore(ctx context.Context, tx *sql.Tx, relID uuid.UUID, initiatorID uuid.UUID, scoreDelta float64) error
}

type postgresRepository struct {
	db *sql.DB
}

func NewRepository(db *sql.DB) Repository {
	return &postgresRepository{db: db}
}

func (r *postgresRepository) BeginTx(ctx context.Context) (*sql.Tx, error) {
	return r.db.BeginTx(ctx, nil)
}

func (r *postgresRepository) GetActiveRelationship(ctx context.Context, tx *sql.Tx, userA uuid.UUID, userB uuid.UUID) (uuid.UUID, error) {
	// Standardize order to prevent duplicates (UUIDs are comparable as strings)
	if userA.String() > userB.String() {
		userA, userB = userB, userA
	}

	var relID uuid.UUID
	err := tx.QueryRowContext(ctx,
		`SELECT id FROM user_relationships WHERE user_a_id = $1 AND user_b_id = $2 AND status = 'ACCEPTED'`,
		userA, userB).Scan(&relID)

	if err == sql.ErrNoRows {
		return uuid.Nil, fmt.Errorf("users are not friends or request is pending")
	}

	return relID, err
}

func (r *postgresRepository) CreateCommitment(ctx context.Context, tx *sql.Tx, c *Commitment) error {
	query := `
		INSERT INTO commitments (rel_id, initiator_id, target_id, entity_id, entity_type, text, category, points, rating, status)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
		RETURNING id, created_at
	`
	return tx.QueryRowContext(ctx, query,
		c.RelID, c.InitiatorID, c.TargetID, c.EntityID, c.EntityType, c.Text, c.Category, c.Points, c.Rating, c.Status,
	).Scan(&c.ID, &c.CreatedAt)
}

func (r *postgresRepository) GetCommitment(ctx context.Context, id uuid.UUID) (*Commitment, error) {
	query := `
		SELECT id, rel_id, initiator_id, target_id, entity_id, entity_type, text, category, points, rating, status, created_at
		FROM commitments WHERE id = $1
	`
	c := &Commitment{}
	err := r.db.QueryRowContext(ctx, query, id).Scan(
		&c.ID, &c.RelID, &c.InitiatorID, &c.TargetID, &c.EntityID, &c.EntityType, &c.Text, &c.Category, &c.Points, &c.Rating, &c.Status, &c.CreatedAt,
	)
	return c, err
}

func (r *postgresRepository) UpdateCommitmentStatus(ctx context.Context, tx *sql.Tx, id uuid.UUID, status CommitmentStatus) error {
	_, err := tx.ExecContext(ctx, `UPDATE commitments SET status = $1 WHERE id = $2`, status, id)
	return err
}

func (r *postgresRepository) UpdateEntityScoreAndGetAverage(ctx context.Context, tx *sql.Tx, entityType EntityType, entityID uuid.UUID, rating int) (float64, error) {
	table := "materialistic_entities"
	if entityType == TypeEmotional {
		table = "emotional_entities"
	}

	query := fmt.Sprintf(`
		UPDATE %s
		SET total_score = total_score + $1, users_votes = users_votes + 1
		WHERE id = $2
		RETURNING total_score, users_votes
	`, table)

	var totalScore int64
	var usersVotes int
	err := tx.QueryRowContext(ctx, query, rating, entityID).Scan(&totalScore, &usersVotes)
	if err != nil {
		return 0, err
	}

	if usersVotes == 0 {
		return 0, nil
	}
	return float64(totalScore) / float64(usersVotes), nil
}

func (r *postgresRepository) InsertOutboxEvent(ctx context.Context, tx *sql.Tx, event *OutboxEvent) error {
	query := `
		INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
		VALUES ($1, $2, $3, $4)
	`
	// Payload is text (JSON), postgres will cast to JSONB
	_, err := tx.ExecContext(ctx, query, event.AggregateType, event.AggregateID, event.EventType, event.Payload)
	return err
}

func (r *postgresRepository) GetOrCreateEntity(ctx context.Context, tx *sql.Tx, entityType EntityType, name string) (uuid.UUID, error) {
	table := "materialistic_entities"
	if entityType == TypeEmotional {
		table = "emotional_entities"
	}

	var entityID uuid.UUID
	query := fmt.Sprintf(`SELECT id FROM %s WHERE name = $1`, table)
	err := tx.QueryRowContext(ctx, query, name).Scan(&entityID)
	
	if err == sql.ErrNoRows {
		insertQuery := fmt.Sprintf(`INSERT INTO %s (name) VALUES ($1) RETURNING id`, table)
		err = tx.QueryRowContext(ctx, insertQuery, name).Scan(&entityID)
	}
	
	return entityID, err
}

func (r *postgresRepository) GetRelationship(ctx context.Context, tx *sql.Tx, relID uuid.UUID) (uuid.UUID, uuid.UUID, error) {
	var a, b uuid.UUID
	err := tx.QueryRowContext(ctx, `SELECT user_a_id, user_b_id FROM user_relationships WHERE id = $1`, relID).Scan(&a, &b)
	return a, b, err
}

func (r *postgresRepository) UpdateReciprocityScore(ctx context.Context, tx *sql.Tx, relID uuid.UUID, initiatorID uuid.UUID, scoreDelta float64) error {
	// We define reciprocity_score as UserA - UserB.
	// So if UserA is the initiator: score += delta
	// If UserB is the initiator: score -= delta
	userA, _, err := r.GetRelationship(ctx, tx, relID)
	if err != nil {
		return err
	}

	query := `UPDATE user_relationships SET reciprocity_score = reciprocity_score + $1 WHERE id = $2`
	if initiatorID != userA {
		scoreDelta = -scoreDelta
	}

	_, err = tx.ExecContext(ctx, query, scoreDelta, relID)
	return err
}
