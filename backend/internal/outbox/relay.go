package outbox

import (
	"context"
	"database/sql"
	"log"
	"time"

	"github.com/Ayush330/symbio/backend/internal/commitments"
	"github.com/Ayush330/symbio/backend/internal/kafka"
)

type Relay struct {
	db       *sql.DB
	producer *kafka.Producer
	interval time.Duration
}

func NewRelay(db *sql.DB, p *kafka.Producer, interval time.Duration) *Relay {
	return &Relay{
		db:       db,
		producer: p,
		interval: interval,
	}
}

func (r *Relay) Start(ctx context.Context) {
	ticker := time.NewTicker(r.interval)
	defer ticker.Stop()

	log.Println("Starting Outbox Relay worker...")

	for {
		select {
		case <-ctx.Done():
			log.Println("Stopping Outbox Relay worker...")
			return
		case <-ticker.C:
			r.processOutbox(ctx)
		}
	}
}

func (r *Relay) processOutbox(ctx context.Context) {
	// 1. Fetch pending events (limit to prevent memory exhaustion)
	events, err := r.fetchEvents(ctx, 100)
	if err != nil {
		log.Printf("Outbox fetch error: %v", err)
		return
	}

	if len(events) == 0 {
		return
	}

	// 2. Publish to Kafka
	var successfullyPublished []string
	for _, event := range events {
		err := r.producer.Publish(ctx, event.AggregateID.String(), []byte(event.Payload))
		if err == nil {
			successfullyPublished = append(successfullyPublished, event.ID.String())
		}
	}

	// 3. Mark as processed (Delete them)
	if len(successfullyPublished) > 0 {
		if err := r.deleteEvents(ctx, successfullyPublished); err != nil {
			log.Printf("Outbox delete error: %v", err)
		} else {
			log.Printf("Successfully relayed %d events to Kafka", len(successfullyPublished))
		}
	}
}

func (r *Relay) fetchEvents(ctx context.Context, limit int) ([]commitments.OutboxEvent, error) {
	query := `
		SELECT id, aggregate_type, aggregate_id, event_type, payload, created_at
		FROM outbox_events
		ORDER BY created_at ASC
		LIMIT $1
	`
	rows, err := r.db.QueryContext(ctx, query, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var events []commitments.OutboxEvent
	for rows.Next() {
		var e commitments.OutboxEvent
		if err := rows.Scan(&e.ID, &e.AggregateType, &e.AggregateID, &e.EventType, &e.Payload, &e.CreatedAt); err != nil {
			return nil, err
		}
		events = append(events, e)
	}
	return events, rows.Err()
}

func (r *Relay) deleteEvents(ctx context.Context, ids []string) error {
	// Building a simple IN clause
	// For production, use sqlx.In or pq.Array
	query := `DELETE FROM outbox_events WHERE id::text IN (`
	args := make([]interface{}, len(ids))
	for i, id := range ids {
		if i > 0 {
			query += ","
		}
		query += "$" + string(rune(i+1+'0')) // Simple integer to parameter logic for small batches
		args[i] = id
	}
	query += `)`

	_, err := r.db.ExecContext(ctx, query, args...)
	return err
}
