package kafka

import (
	"context"
	"log"
	"os"

	"github.com/segmentio/kafka-go"
)

type Producer struct {
	writer *kafka.Writer
}

func NewProducer() *Producer {
	broker := os.Getenv("KAFKA_BROKER")
	if broker == "" {
		broker = "localhost:9092"
	}

	w := &kafka.Writer{
		Addr:     kafka.TCP(broker),
		Topic:    "activity_logs",
		Balancer: &kafka.LeastBytes{},
	}

	return &Producer{writer: w}
}

func (p *Producer) Publish(ctx context.Context, key string, msg []byte) error {
	err := p.writer.WriteMessages(ctx,
		kafka.Message{
			Key:   []byte(key),
			Value: msg,
		},
	)
	if err != nil {
		log.Printf("Failed to publish message to Kafka: %v", err)
	}
	return err
}

func (p *Producer) Close() error {
	return p.writer.Close()
}
