package db

import (
	"context"
	"fmt"
	"os"

	"github.com/redis/go-redis/v9"
)

func NewRedisClient() (*redis.Client, error) {
	host := os.Getenv("REDIS_HOST")
	if host == "" {
		host = "127.0.0.1"
	}
	port := os.Getenv("REDIS_PORT")
	if port == "" {
		port = "6379"
	}

	addr := fmt.Sprintf("%s:%s", host, port)
	rdb := redis.NewClient(&redis.Options{
		Addr:     addr,
		Password: "", // no password set
		DB:       0,  // use default DB
	})

	// Ping to check connection
	_, err := rdb.Ping(context.Background()).Result()
	if err != nil {
		return nil, err
	}

	return rdb, nil
}
