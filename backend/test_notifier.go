package main

import (
	"context"
	"database/sql"
	"fmt"
	"log"
	"os"

	"github.com/Ayush330/symbio/backend/internal/notifications"
	"github.com/google/uuid"
	_ "github.com/lib/pq"
)

func main() {
	if len(os.Args) < 2 {
		log.Fatal("Usage: go run test_notifier.go <YOUR_USER_ID>")
	}
	targetUserID, err := uuid.Parse(os.Args[1])
	if err != nil {
		log.Fatalf("Invalid UUID: %v", err)
	}

	// 1. Connect to DB
	db, err := sql.Open("postgres", "host=localhost port=5432 user=ayush_admin password=password dbname=symbio_db sslmode=disable")
	if err != nil {
		log.Fatalf("DB Connect error: %v", err)
	}
	defer db.Close()

	// 2. Initialize FCM
	fcmService, err := notifications.NewFCMService("firebase-adminsdk.json")
	if err != nil {
		log.Fatalf("FCM Init error: %v", err)
	}

	// 3. Find Phantom User
	var phantomIDStr string
	err = db.QueryRow("SELECT id FROM users WHERE email = 'phantom@test.com'").Scan(&phantomIDStr)
	if err != nil {
		log.Fatalf("Could not find Phantom user. Did you run the INSERT command? %v", err)
	}
	phantomID := uuid.MustParse(phantomIDStr)

	// 4. Create the relationship (PENDING)
	relID := uuid.New()
	_, err = db.Exec("INSERT INTO user_relationships (id, user_a_id, user_b_id, initiator_id, status) VALUES ($1, $2, $3, $4, 'PENDING')", 
		relID, phantomID, targetUserID, phantomID)
	if err != nil {
		log.Fatalf("Relationship creation error: %v", err)
	}

	// 5. Fetch Your Token and Name
	var targetToken, targetName string
	err = db.QueryRow("SELECT fcm_token, name FROM users WHERE id = $1", targetUserID).Scan(&targetToken, &targetName)
	if err != nil {
		log.Fatalf("Error fetching your token: %v", err)
	}

	if targetToken == "" {
		log.Fatal("FATAL: Your FCM token is empty. Make sure you signed up on a REAL device and granted notification permission.")
	}

	// 6. Send the Notification manually
	fmt.Printf("Sending notification to %s (%s)...\n", targetName, targetUserID)
	err = fcmService.SendPushNotification(context.Background(), targetToken, 
		"New Friend Request!", 
		"Phantom Boy wants to connect with you on Symbio!", 
		map[string]string{
			"type": "friend_request",
			"id": phantomID.String(),
		})

	if err != nil {
		log.Fatalf("Push failed: %v", err)
	}

	fmt.Println("✅ Notification sent! Check your phone.")
}
