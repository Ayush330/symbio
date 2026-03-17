package commitments

import (
	"context"
	"database/sql"
	"fmt"
	"log"
	"time"

	"github.com/google/uuid"
)

type CommitmentStatus string

const (
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
	Text        string           `json:"text,omitempty"`
	Category    string           `json:"category,omitempty"`
	Points      int              `json:"points"`
	Rating      int              `json:"rating"`
	Status      CommitmentStatus `json:"status"`
	CreatedAt   time.Time        `json:"created_at"`
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
	TargetUserID string `json:"target_user_id"`
	Rating       int    `json:"rating,omitempty"` // 1-100
	Text         string `json:"text,omitempty"`
	Category     string `json:"category,omitempty"`
	Points       int    `json:"points,omitempty"`
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
	InsertOutboxEvent(ctx context.Context, tx *sql.Tx, event *OutboxEvent) error
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
		INSERT INTO commitments (rel_id, initiator_id, target_id, text, category, points, rating, status)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
		RETURNING id, created_at
	`
	return tx.QueryRowContext(ctx, query,
		c.RelID, c.InitiatorID, c.TargetID, c.Text, c.Category, c.Points, c.Rating, c.Status,
	).Scan(&c.ID, &c.CreatedAt)
}

func (r *postgresRepository) GetCommitment(ctx context.Context, id uuid.UUID) (*Commitment, error) {
	query := `
		SELECT id, rel_id, initiator_id, target_id, text, category, points, rating, status, created_at
		FROM commitments WHERE id = $1
	`
	c := &Commitment{}
	err := r.db.QueryRowContext(ctx, query, id).Scan(
		&c.ID, &c.RelID, &c.InitiatorID, &c.TargetID, &c.Text, &c.Category, &c.Points, &c.Rating, &c.Status, &c.CreatedAt,
	)
	return c, err
}

func (r *postgresRepository) UpdateCommitmentStatus(ctx context.Context, tx *sql.Tx, id uuid.UUID, status CommitmentStatus) error {
	_, err := tx.ExecContext(ctx, `UPDATE commitments SET status = $1 WHERE id = $2`, status, id)
	return err
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

func (r *postgresRepository) GetRelationship(ctx context.Context, tx *sql.Tx, relID uuid.UUID) (uuid.UUID, uuid.UUID, error) {
	var a, b uuid.UUID
	err := tx.QueryRowContext(ctx, `SELECT user_a_id, user_b_id FROM user_relationships WHERE id = $1`, relID).Scan(&a, &b)
	return a, b, err
}

func (r *postgresRepository) UpdateReciprocityScore(ctx context.Context, tx *sql.Tx, relID uuid.UUID, initiatorID uuid.UUID, scoreDelta float64) error {
	// We define reciprocity_score as UserA - UserB.
	// So if UserA is the initiator: score += delta
	// If UserB is the initiator: score -= delta
	userA, userB, err := r.GetRelationship(ctx, tx, relID)
	if err != nil {
		return err
	}

	log.Printf("DEBUG: Updating reciprocity for rel %s, initiator %s, delta %f. UserA %s, UserB %s", relID, initiatorID, scoreDelta, userA, userB)

	query := `UPDATE user_relationships SET reciprocity_score = reciprocity_score + $1 WHERE id = $2`
	if initiatorID != userA {
		log.Printf("DEBUG: Initiator is UserB, inverting delta")
		scoreDelta = -scoreDelta
	} else {
		log.Printf("DEBUG: Initiator is UserA, applying delta as is")
	}

	res, err := tx.ExecContext(ctx, query, scoreDelta, relID)
	if err != nil {
		return err
	}
	rows, _ := res.RowsAffected()
	log.Printf("DEBUG: Updated %d row(s) with new delta %f", rows, scoreDelta)
	return nil
}
