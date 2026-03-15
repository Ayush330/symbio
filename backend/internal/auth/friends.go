package auth

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"

	"github.com/Ayush330/symbio/backend/internal/transport"
	"github.com/google/uuid"
)

// PushSender allows sending push notifications
type PushSender interface {
	SendPushNotification(ctx context.Context, token, title, body string, data map[string]string) error
}

// FriendsHandler handles friend-related HTTP endpoints
type FriendsHandler struct {
	db         *sql.DB
	service    Service
	pushSender PushSender
}

func NewFriendsHandler(db *sql.DB, s Service, push PushSender) *FriendsHandler {
	return &FriendsHandler{db: db, service: s, pushSender: push}
}

type FriendInfo struct {
	ID                 uuid.UUID `json:"id"`
	Name               string    `json:"name"`
	Email              string    `json:"email"`
	Phone              string    `json:"phone,omitempty"`
	RelationshipID     uuid.UUID `json:"relationship_id"`
	RelationshipHealth float64   `json:"relationship_health"`
}

// ListFriends returns all friends of the authenticated user with relationship health
func (h *FriendsHandler) ListFriends(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		transport.SendError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}

	userID, err := extractUserID(r)
	if err != nil {
		transport.SendError(w, http.StatusUnauthorized, "Unauthorized")
		return
	}

	query := `
		SELECT
			u.id, u.name, u.email, COALESCE(u.phone, ''),
			ur.id AS rel_id, ur.reciprocity_score
		FROM user_relationships ur
		JOIN users u ON (
			(ur.user_a_id = $1 AND u.id = ur.user_b_id) OR
			(ur.user_b_id = $1 AND u.id = ur.user_a_id)
		)
		WHERE (ur.user_a_id = $1 OR ur.user_b_id = $1)
		  AND ur.status = 'ACCEPTED'
	`

	rows, err := h.db.QueryContext(r.Context(), query, userID)
	if err != nil {
		transport.SendError(w, http.StatusInternalServerError, "Internal server error")
		return
	}
	defer rows.Close()

	friends := []FriendInfo{}
	for rows.Next() {
		var f FriendInfo
		if err := rows.Scan(&f.ID, &f.Name, &f.Email, &f.Phone, &f.RelationshipID, &f.RelationshipHealth); err != nil {
			transport.SendError(w, http.StatusInternalServerError, "Internal server error")
			return
		}
		friends = append(friends, f)
	}

	transport.WriteJSON(w, http.StatusOK, friends)
}

// ListFriendRequests returns pending incoming friend requests
func (h *FriendsHandler) ListFriendRequests(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		transport.SendError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}

	userID, err := extractUserID(r)
	if err != nil {
		transport.SendError(w, http.StatusUnauthorized, "Unauthorized")
		return
	}

	query := `
		SELECT
			u.id, u.name, u.email, COALESCE(u.phone, ''),
			ur.id AS rel_id, ur.reciprocity_score
		FROM user_relationships ur
		JOIN users u ON u.id = ur.initiator_id
		WHERE (ur.user_a_id = $1 OR ur.user_b_id = $1)
		  AND ur.status = 'PENDING'
		  AND ur.initiator_id != $1
	`

	rows, err := h.db.QueryContext(r.Context(), query, userID)
	if err != nil {
		transport.SendError(w, http.StatusInternalServerError, "Internal server error")
		return
	}
	defer rows.Close()

	friends := []FriendInfo{}
	for rows.Next() {
		var f FriendInfo
		if err := rows.Scan(&f.ID, &f.Name, &f.Email, &f.Phone, &f.RelationshipID, &f.RelationshipHealth); err != nil {
			transport.SendError(w, http.StatusInternalServerError, "Internal server error")
			return
		}
		friends = append(friends, f)
	}

	transport.WriteJSON(w, http.StatusOK, friends)
}

// SendFriendRequest sends a friend request to another user
func (h *FriendsHandler) SendFriendRequest(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		transport.SendError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}

	initiatorID, err := extractUserID(r)
	if err != nil {
		transport.SendError(w, http.StatusUnauthorized, "Unauthorized")
		return
	}

	var req struct {
		TargetID string `json:"target_id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.TargetID == "" {
		transport.SendError(w, http.StatusBadRequest, "Invalid request body")
		return
	}

	// Standardize UUID ordering to prevent duplicates
	uid1, uid2 := initiatorID, req.TargetID
	if uid1 > uid2 {
		uid1, uid2 = uid2, uid1
	}

	_, err = h.db.ExecContext(r.Context(), `
		INSERT INTO user_relationships (user_a_id, user_b_id, initiator_id, status)
		VALUES ($1, $2, $3, 'PENDING')
		ON CONFLICT (user_a_id, user_b_id) DO NOTHING
	`, uid1, uid2, initiatorID)

	if err != nil {
		transport.SendError(w, http.StatusInternalServerError, "Failed to send request")
		return
	}

	// Async push notification
	go func() {
		initiator, _ := h.service.(*authService).repo.GetUserByID(context.Background(), uuid.MustParse(initiatorID))
		target, _ := h.service.(*authService).repo.GetUserByID(context.Background(), uuid.MustParse(req.TargetID))
		if target != nil && target.FCMToken != "" {
			title := "New Friend Request"
			body := fmt.Sprintf("%s wants to connect with you on Symbio!", initiator.Name)
			h.pushSender.SendPushNotification(context.Background(), target.FCMToken, title, body, map[string]string{
				"type": "friend_request",
				"id":   initiatorID,
			})
		}
	}()

	transport.WriteJSON(w, http.StatusCreated, map[string]bool{"success": true})
}

// AcceptFriendRequest accepts a pending friend request
func (h *FriendsHandler) AcceptFriendRequest(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		transport.SendError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}

	userID, err := extractUserID(r)
	if err != nil {
		transport.SendError(w, http.StatusUnauthorized, "Unauthorized")
		return
	}

	var req struct {
		RelID string `json:"rel_id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.RelID == "" {
		transport.SendError(w, http.StatusBadRequest, "Invalid request body")
		return
	}

	res, err := h.db.ExecContext(r.Context(), `
		UPDATE user_relationships 
		SET status = 'ACCEPTED'
		WHERE id = $1 AND (user_a_id = $2 OR user_b_id = $2) AND initiator_id != $2 AND status = 'PENDING'
	`, req.RelID, userID)

	if err != nil {
		transport.SendError(w, http.StatusInternalServerError, "Internal server error")
		return
	}

	rows, _ := res.RowsAffected()
	if rows == 0 {
		transport.SendError(w, http.StatusNotFound, "Request not found or unauthorized")
		return
	}

	// Async push notification
	go func() {
		var initiatorIDStr string
		err := h.db.QueryRowContext(context.Background(), "SELECT initiator_id FROM user_relationships WHERE id = $1", req.RelID).Scan(&initiatorIDStr)
		if err == nil {
			initiatorID, _ := uuid.Parse(initiatorIDStr)
			accepter, _ := h.service.(*authService).repo.GetUserByID(context.Background(), uuid.MustParse(userID))
			initiator, _ := h.service.(*authService).repo.GetUserByID(context.Background(), initiatorID)
			if initiator != nil && initiator.FCMToken != "" {
				title := "Friend Request Accepted!"
				body := fmt.Sprintf("%s has accepted your friend request. You can now build commitments together!", accepter.Name)
				h.pushSender.SendPushNotification(context.Background(), initiator.FCMToken, title, body, map[string]string{
					"type": "friend_accepted",
					"id":   userID,
				})
			}
		}
	}()

	transport.WriteJSON(w, http.StatusOK, map[string]bool{"success": true})
}

// RejectFriendRequest rejects a pending friend request (deletes it)
func (h *FriendsHandler) RejectFriendRequest(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		transport.SendError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}

	userID, err := extractUserID(r)
	if err != nil {
		transport.SendError(w, http.StatusUnauthorized, "Unauthorized")
		return
	}

	var req struct {
		RelID string `json:"rel_id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.RelID == "" {
		transport.SendError(w, http.StatusBadRequest, "Invalid request body")
		return
	}

	res, err := h.db.ExecContext(r.Context(), `
		DELETE FROM user_relationships 
		WHERE id = $1 AND (user_a_id = $2 OR user_b_id = $2) AND status = 'PENDING'
	`, req.RelID, userID)

	if err != nil {
		transport.SendError(w, http.StatusInternalServerError, "Internal server error")
		return
	}

	rows, _ := res.RowsAffected()
	if rows == 0 {
		transport.SendError(w, http.StatusNotFound, "Request not found or unauthorized")
		return
	}

	transport.WriteJSON(w, http.StatusOK, map[string]bool{"success": true})
}

// LookupUser checks if a user exists by email
func (h *FriendsHandler) LookupUser(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		transport.SendError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}

	email := r.URL.Query().Get("email")
	if email == "" {
		transport.SendError(w, http.StatusBadRequest, "email parameter required")
		return
	}

	var userID uuid.UUID
	var name string
	err := h.db.QueryRowContext(r.Context(),
		`SELECT id, name FROM users WHERE email = $1`, email,
	).Scan(&userID, &name)

	if err == sql.ErrNoRows {
		transport.WriteJSON(w, http.StatusOK, map[string]interface{}{
			"exists": false,
		})
		return
	}
	if err != nil {
		transport.SendError(w, http.StatusInternalServerError, "Internal server error")
		return
	}

	transport.WriteJSON(w, http.StatusOK, map[string]interface{}{
		"exists":  true,
		"user_id": userID.String(),
		"name":    name,
	})
}

// GetFriendActivity returns recent commitments for a relationship
func (h *FriendsHandler) GetFriendActivity(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		transport.SendError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}

	userID, err := extractUserID(r)
	if err != nil {
		transport.SendError(w, http.StatusUnauthorized, "Unauthorized")
		return
	}

	// Extract friend ID from path: /friends/{id}/activity
	parts := strings.Split(strings.TrimPrefix(r.URL.Path, "/friends/"), "/")
	if len(parts) < 2 || parts[1] != "activity" {
		transport.SendError(w, http.StatusBadRequest, "Invalid path")
		return
	}
	friendID := parts[0]

	// Find relationship between the two users
	query := `
		SELECT ur.id FROM user_relationships ur
		WHERE (ur.user_a_id = $1 AND ur.user_b_id = $2)
		   OR (ur.user_a_id = $2 AND ur.user_b_id = $1)
	`
	var relID uuid.UUID
	err = h.db.QueryRowContext(r.Context(), query, userID, friendID).Scan(&relID)
	if err != nil {
		transport.SendError(w, http.StatusNotFound, "Relationship not found")
		return
	}

	// Fetch recent commitments for this relationship
	activityQuery := `
		SELECT c.id, c.initiator_id, c.target_id, c.entity_type, c.rating, c.status, c.created_at,
			COALESCE(me.name, ee.name, 'Unknown') AS entity_name,
			u.name AS initiator_name
		FROM commitments c
		LEFT JOIN materialistic_entities me ON c.entity_type = 'MATERIAL' AND c.entity_id = me.id
		LEFT JOIN emotional_entities ee ON c.entity_type = 'EMOTIONAL' AND c.entity_id = ee.id
		LEFT JOIN users u ON c.initiator_id = u.id
		WHERE c.rel_id = $1
		ORDER BY c.created_at DESC
		LIMIT 20
	`

	rows, err := h.db.QueryContext(r.Context(), activityQuery, relID)
	if err != nil {
		transport.SendError(w, http.StatusInternalServerError, "Internal server error")
		return
	}
	defer rows.Close()

	type ActivityItem struct {
		ID            uuid.UUID `json:"id"`
		InitiatorID   uuid.UUID `json:"initiator_id"`
		TargetID      uuid.UUID `json:"target_id"`
		EntityType    string    `json:"entity_type"`
		EntityName    string    `json:"entity_name"`
		InitiatorName string    `json:"initiator_name"`
		Rating        int       `json:"rating"`
		Status        string    `json:"status"`
		CreatedAt     string    `json:"created_at"`
	}

	activities := []ActivityItem{}
	for rows.Next() {
		var a ActivityItem
		var createdAt interface{}
		if err := rows.Scan(&a.ID, &a.InitiatorID, &a.TargetID, &a.EntityType, &a.Rating, &a.Status, &createdAt, &a.EntityName, &a.InitiatorName); err != nil {
			transport.SendError(w, http.StatusInternalServerError, "Internal server error")
			return
		}
		a.CreatedAt = createdAt.(interface{ String() string }).String()
		activities = append(activities, a)
	}

	transport.WriteJSON(w, http.StatusOK, activities)
}

// extractUserID extracts user ID from JWT token in Authorization header
func extractUserID(r *http.Request) (string, error) {
	auth := r.Header.Get("Authorization")
	if auth == "" {
		return "", ErrInvalidCredentials
	}

	tokenStr := strings.TrimPrefix(auth, "Bearer ")
	claims, err := ParseJWT(tokenStr)
	if err != nil {
		return "", err
	}

	sub, ok := claims["sub"].(string)
	if !ok {
		return "", ErrInvalidCredentials
	}

	return sub, nil
}
