package auth

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"math"
	"net/http"
	"strconv"
	"strings"
	"time"

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
	KarmaScore         float64   `json:"karma_score"`
}

func calculateKarmaScore(favours, points int) float64 {
	// Formula: S(x, y) = 1 + 99 * (1 - e^-(0.05*x + 0.005*y))
	k_x := 0.05
	k_y := 0.005
	val := k_x*float64(favours) + k_y*float64(points)
	score := 1.0 + 99.0*(1.0-math.Exp(-val))
	return score
}

// ListFriends returns all friends of the authenticated user with relationship health
func (h *FriendsHandler) ListFriends(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		transport.SendError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}

	userUUID, err := ExtractUserID(r)
	if err != nil {
		transport.SendError(w, http.StatusUnauthorized, "Unauthorized")
		return
	}

	query := `
		SELECT
			u.id, u.name, u.email, COALESCE(u.phone, ''),
			ur.id AS rel_id, ur.reciprocity_score, ur.user_a_id,
			COUNT(c.id) FILTER (WHERE c.status = 'ACKNOWLEDGED') as count_favours,
			COALESCE(SUM(c.points) FILTER (WHERE c.status = 'ACKNOWLEDGED'), 0) as total_points
		FROM user_relationships ur
		JOIN users u ON (
			(ur.user_a_id = $1 AND u.id = ur.user_b_id) OR
			(ur.user_b_id = $1 AND u.id = ur.user_a_id)
		)
		LEFT JOIN commitments c ON c.rel_id = ur.id
		WHERE (ur.user_a_id = $1 OR ur.user_b_id = $1)
		  AND ur.status = 'ACCEPTED'
		GROUP BY u.id, ur.id
	`

	rows, err := h.db.QueryContext(r.Context(), query, userUUID)
	if err != nil {
		log.Printf("DB Query Error (ListFriends): %v", err)
		transport.SendError(w, http.StatusInternalServerError, "Internal server error")
		return
	}
	defer rows.Close()

	friends := []FriendInfo{}
	for rows.Next() {
		var f FriendInfo
		var score float64
		var userA uuid.UUID
		var countFavours, totalPoints int
		if err := rows.Scan(&f.ID, &f.Name, &f.Email, &f.Phone, &f.RelationshipID, &score, &userA, &countFavours, &totalPoints); err != nil {
			transport.SendError(w, http.StatusInternalServerError, "Internal server error")
			return
		}
		// Reciprocity score is UserA - UserB. 
		// If requesting user is UserB, invert it so it's relative to them.
		if userUUID != userA {
			score = -score
		}
		f.RelationshipHealth = score
		f.KarmaScore = calculateKarmaScore(countFavours, totalPoints)
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

	userUUID, err := ExtractUserID(r)
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

	rows, err := h.db.QueryContext(r.Context(), query, userUUID)
	if err != nil {
		log.Printf("DB Query Error (ListFriendRequests): %v", err)
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

	initiatorID, err := ExtractUserID(r)
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

	targetUUID, err := uuid.Parse(req.TargetID)
	if err != nil {
		transport.SendError(w, http.StatusBadRequest, "Invalid target ID")
		return
	}

	uid1, uid2 := initiatorID, targetUUID
	if strings.Compare(uid1.String(), uid2.String()) > 0 {
		uid1, uid2 = uid2, uid1
	}

	// Check if relationship already exists
	var existingStatus string
	err = h.db.QueryRowContext(r.Context(), `
		SELECT status FROM user_relationships 
		WHERE (user_a_id = $1 AND user_b_id = $2)
	`, uid1, uid2).Scan(&existingStatus)
	
	if err == nil {
		if existingStatus == "ACCEPTED" {
			transport.SendError(w, http.StatusConflict, "You are already friends with this user")
			return
		}
		if existingStatus == "PENDING" {
			transport.SendError(w, http.StatusConflict, "A friend request is already pending")
			return
		}
	}

	_, err = h.db.ExecContext(r.Context(), `
		INSERT INTO user_relationships (user_a_id, user_b_id, initiator_id, status)
		VALUES ($1, $2, $3, 'PENDING')
		ON CONFLICT (user_a_id, user_b_id) DO UPDATE 
		SET status = 'PENDING', initiator_id = EXCLUDED.initiator_id
	`, uid1, uid2, initiatorID)

	if err != nil {
		transport.SendError(w, http.StatusInternalServerError, "Failed to send request")
		return
	}

	// Async push notification
	if h.pushSender != nil {
		go func() {
			initiator, _ := h.service.(*authService).repo.GetUserByID(context.Background(), initiatorID)
			target, _ := h.service.(*authService).repo.GetUserByID(context.Background(), targetUUID)
			if target != nil && target.FCMToken != "" {
				title := "New Friend Request"
				body := fmt.Sprintf("%s wants to connect with you on Kizuna!", initiator.Name)
				h.pushSender.SendPushNotification(context.Background(), target.FCMToken, title, body, map[string]string{
					"type": "friend_request",
					"id":   initiatorID.String(),
				})
			}
		}()
	}

	transport.WriteJSON(w, http.StatusCreated, map[string]bool{"success": true})
}

// AcceptFriendRequest accepts a pending friend request
func (h *FriendsHandler) AcceptFriendRequest(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		transport.SendError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}

	userUUID, err := ExtractUserID(r)
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

	relUUID, err := uuid.Parse(req.RelID)
	if err != nil {
		transport.SendError(w, http.StatusBadRequest, "Invalid relationship ID")
		return
	}

	res, err := h.db.ExecContext(r.Context(), `
		UPDATE user_relationships 
		SET status = 'ACCEPTED'
		WHERE id = $1 AND (user_a_id = $2 OR user_b_id = $2) AND initiator_id != $2 AND status = 'PENDING'
	`, relUUID, userUUID)

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
	if h.pushSender != nil {
		go func() {
			var initiatorID uuid.UUID
			err := h.db.QueryRowContext(context.Background(), "SELECT initiator_id FROM user_relationships WHERE id = $1", relUUID).Scan(&initiatorID)
			if err == nil {
				accepter, _ := h.service.(*authService).repo.GetUserByID(context.Background(), userUUID)
				initiator, _ := h.service.(*authService).repo.GetUserByID(context.Background(), initiatorID)
				if initiator != nil && initiator.FCMToken != "" {
					title := "Friend Request Accepted!"
					body := fmt.Sprintf("%s has accepted your friend request. You can now build commitments together!", accepter.Name)
					h.pushSender.SendPushNotification(context.Background(), initiator.FCMToken, title, body, map[string]string{
						"type": "friend_accepted",
						"id":   userUUID.String(),
					})
				}
			}
		}()
	}

	transport.WriteJSON(w, http.StatusOK, map[string]bool{"success": true})
}

// RejectFriendRequest rejects a pending friend request (deletes it)
func (h *FriendsHandler) RejectFriendRequest(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		transport.SendError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}

	userUUID, err := ExtractUserID(r)
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

	relUUID, err := uuid.Parse(req.RelID)
	if err != nil {
		transport.SendError(w, http.StatusBadRequest, "Invalid relationship ID")
		return
	}

	res, err := h.db.ExecContext(r.Context(), `
		DELETE FROM user_relationships 
		WHERE id = $1 AND (user_a_id = $2 OR user_b_id = $2) AND status = 'PENDING'
	`, relUUID, userUUID)

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

// LookupUser checks if a user exists by email or phone
func (h *FriendsHandler) LookupUser(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		transport.SendError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}

	email := r.URL.Query().Get("email")
	phone := r.URL.Query().Get("phone")

	if email == "" && phone == "" {
		transport.SendError(w, http.StatusBadRequest, "email or phone parameter required")
		return
	}

	var userID uuid.UUID
	var name string
	var err error

	if email != "" {
		err = h.db.QueryRowContext(r.Context(), 
			`SELECT id, name FROM users WHERE LOWER(email) = LOWER($1)`, email,
		).Scan(&userID, &name)
	} else {
		err = h.db.QueryRowContext(r.Context(), 
			`SELECT id, name FROM users WHERE phone = $1`, phone,
		).Scan(&userID, &name)
	}

	if err == sql.ErrNoRows {
		transport.WriteJSON(w, http.StatusOK, map[string]interface{}{
			"exists": false,
		})
		return
	}
	if err != nil {
		log.Printf("DB Query Error (LookupUser): %v", err)
		transport.SendError(w, http.StatusInternalServerError, "Internal server error")
		return
	}

	transport.WriteJSON(w, http.StatusOK, map[string]interface{}{
		"exists":  true,
		"user_id": userID.String(),
		"name":    name,
	})
}

// SendInvite sends an invitation to a new user (via SMS or Email)
func (h *FriendsHandler) SendInvite(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		transport.SendError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}

	userUUID, err := ExtractUserID(r)
	if err != nil {
		transport.SendError(w, http.StatusUnauthorized, "Unauthorized")
		return
	}

	var req struct {
		Phone string `json:"phone,omitempty"`
		Email string `json:"email,omitempty"`
		Name  string `json:"name,omitempty"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		transport.SendError(w, http.StatusBadRequest, "Invalid request body")
		return
	}

	if req.Phone == "" && req.Email == "" {
		transport.SendError(w, http.StatusBadRequest, "phone or email is required")
		return
	}

	// For now, we just log the invite and notify the user
	// In a real app, this would trigger SMS via Twilio or Email via SendGrid
	log.Printf("INVITE: User %s invited %s (Email: %s, Phone: %s)", userUUID, req.Name, req.Email, req.Phone)

	transport.WriteJSON(w, http.StatusOK, map[string]bool{"success": true})
}

type ActivityItem struct {
	ID            uuid.UUID `json:"id"`
	InitiatorID   uuid.UUID `json:"initiator_id"`
	TargetID      uuid.UUID `json:"target_id"`
	Text          string    `json:"text"`
	Category      string    `json:"category"`
	Points        int       `json:"points"`
	Rating        int       `json:"rating"`
	Status        string    `json:"status"`
	CreatedAt     string    `json:"created_at"`
	InitiatorName string    `json:"initiator_name"`
}

type ActivityGroup struct {
	Month string         `json:"month"`
	Items []ActivityItem `json:"items"`
}

// GetFriendActivity returns recent commitments for a relationship
func (h *FriendsHandler) GetFriendActivity(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		transport.SendError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}

	userUUID, err := ExtractUserID(r)
	if err != nil {
		transport.SendError(w, http.StatusUnauthorized, "Unauthorized")
		return
	}

	parts := strings.Split(strings.TrimPrefix(r.URL.Path, "/friends/"), "/")
	if len(parts) < 2 || parts[1] != "activity" {
		transport.SendError(w, http.StatusBadRequest, "Invalid path")
		return
	}
	friendUUID, err := uuid.Parse(parts[0])
	if err != nil {
		transport.SendError(w, http.StatusBadRequest, "Invalid friend ID")
		return
	}

	// Find relationship
	var relID uuid.UUID
	err = h.db.QueryRowContext(r.Context(), `
		SELECT id FROM user_relationships 
		WHERE (user_a_id = $1 AND user_b_id = $2) OR (user_a_id = $2 AND user_b_id = $1)
	`, userUUID, friendUUID).Scan(&relID)
	
	if err != nil {
		transport.SendError(w, http.StatusNotFound, "Relationship not found")
		return
	}

	limit, offset := parseLimitOffset(r)

	query := `
		SELECT c.id, c.initiator_id, c.target_id, COALESCE(c.text, ''), COALESCE(c.category, ''), c.points, c.rating, c.status, c.created_at,
			u.name AS initiator_name
		FROM commitments c
		LEFT JOIN users u ON c.initiator_id = u.id
		WHERE c.rel_id = $1
		ORDER BY c.created_at DESC
		LIMIT $2 OFFSET $3
	`

	rows, err := h.db.QueryContext(r.Context(), query, relID, limit, offset)
	if err != nil {
		transport.SendError(w, http.StatusInternalServerError, "Internal server error")
		return
	}
	defer rows.Close()

	items := []ActivityItem{}
	for rows.Next() {
		var a ActivityItem
		var createdAt time.Time
		if err := rows.Scan(&a.ID, &a.InitiatorID, &a.TargetID, &a.Text, &a.Category, &a.Points, &a.Rating, &a.Status, &createdAt, &a.InitiatorName); err != nil {
			continue
		}
		a.CreatedAt = createdAt.Format(time.RFC3339)
		items = append(items, a)
	}

	transport.WriteJSON(w, http.StatusOK, items)
}

// GetGlobalActivity returns all user interactons grouped by month for the main activity tab
func (h *FriendsHandler) GetGlobalActivity(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		transport.SendError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}

	userUUID, err := ExtractUserID(r)
	if err != nil {
		transport.SendError(w, http.StatusUnauthorized, "Unauthorized")
		return
	}

	limit, offset := parseLimitOffset(r)

	query := `
		SELECT c.id, c.initiator_id, c.target_id, COALESCE(c.text, ''), COALESCE(c.category, ''), c.points, c.rating, c.status, c.created_at,
			u.name AS initiator_name
		FROM commitments c
		LEFT JOIN users u ON c.initiator_id = u.id
		WHERE c.initiator_id = $1 OR c.target_id = $1
		ORDER BY c.created_at DESC
		LIMIT $2 OFFSET $3
	`

	rows, err := h.db.QueryContext(r.Context(), query, userUUID, limit, offset)
	if err != nil {
		log.Printf("DB Query Error (GetGlobalActivity): %v", err)
		transport.SendError(w, http.StatusInternalServerError, "Internal server error")
		return
	}
	defer rows.Close()

	var groups []ActivityGroup
	var currentGroup *ActivityGroup

	for rows.Next() {
		var a ActivityItem
		var createdAt time.Time
		if err := rows.Scan(&a.ID, &a.InitiatorID, &a.TargetID, &a.Text, &a.Category, &a.Points, &a.Rating, &a.Status, &createdAt, &a.InitiatorName); err != nil {
			log.Printf("Scan error: %v", err)
			continue
		}
		a.CreatedAt = createdAt.Format(time.RFC3339)
		
		month := createdAt.Format("January 2006")
		if currentGroup == nil || currentGroup.Month != month {
			groups = append(groups, ActivityGroup{
				Month: month,
				Items: []ActivityItem{a},
			})
			currentGroup = &groups[len(groups)-1]
		} else {
			currentGroup.Items = append(currentGroup.Items, a)
		}
	}

	transport.WriteJSON(w, http.StatusOK, groups)
}

func parseLimitOffset(r *http.Request) (int, int) {
	limitStr := r.URL.Query().Get("limit")
	offsetStr := r.URL.Query().Get("offset")
	limit, _ := strconv.Atoi(limitStr)
	offset, _ := strconv.Atoi(offsetStr)
	if limit <= 0 { limit = 20 }
	if offset < 0 { offset = 0 }
	return limit, offset
}

// GetRelationshipStats returns detailed reciprocity stats and color for a friend
func (h *FriendsHandler) GetRelationshipStats(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		transport.SendError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}

	userUUID, err := ExtractUserID(r)
	if err != nil {
		transport.SendError(w, http.StatusUnauthorized, "Unauthorized")
		return
	}

	parts := strings.Split(strings.TrimPrefix(r.URL.Path, "/relationship/"), "/")
	if len(parts) < 1 || parts[0] == "" {
		transport.SendError(w, http.StatusBadRequest, "Friend ID is required")
		return
	}
	friendID, err := uuid.Parse(parts[0])
	if err != nil {
		transport.SendError(w, http.StatusBadRequest, "Invalid friend ID")
		return
	}

	var score float64
	var userA uuid.UUID
	var totalGiven, totalReceived int
	var pointsGiven, pointsReceived int

	query := `
		SELECT ur.reciprocity_score, ur.user_a_id,
			(SELECT COUNT(*) FROM commitments WHERE rel_id = ur.id AND initiator_id = $1 AND status = 'ACKNOWLEDGED') as given,
			(SELECT COUNT(*) FROM commitments WHERE rel_id = ur.id AND target_id = $1 AND status = 'ACKNOWLEDGED') as received,
			(SELECT COALESCE(SUM(points), 0) FROM commitments WHERE rel_id = ur.id AND initiator_id = $1 AND status = 'ACKNOWLEDGED') as pts_given,
			(SELECT COALESCE(SUM(points), 0) FROM commitments WHERE rel_id = ur.id AND target_id = $1 AND status = 'ACKNOWLEDGED') as pts_received
		FROM user_relationships ur
		WHERE (ur.user_a_id = $1 AND ur.user_b_id = $2) OR (ur.user_a_id = $2 AND ur.user_b_id = $1)
	`
	err = h.db.QueryRowContext(r.Context(), query, userUUID, friendID).Scan(&score, &userA, &totalGiven, &totalReceived, &pointsGiven, &pointsReceived)
	if err != nil {
		log.Printf("DB Query Error (GetRelationshipStats): %v", err)
		transport.SendError(w, http.StatusNotFound, "Relationship not found")
		return
	}

	// Score is UserA - UserB relative. Adjust if requester is UserB.
	if userUUID != userA {
		score = -score
	}

	color := "yellow"
	if score > 50 {
		color = "green"
	} else if score < -50 {
		color = "red"
	}

	transport.WriteJSON(w, http.StatusOK, map[string]interface{}{
		"score":           score,
		"karma_score":     calculateKarmaScore(totalGiven+totalReceived, pointsGiven+pointsReceived),
		"color":           color,
		"total_given":     totalGiven,
		"total_received":  totalReceived,
		"points_given":    pointsGiven,
		"points_received": pointsReceived,
	})
}

// GetProfileStats returns global stats for the current user
func (h *FriendsHandler) GetProfileStats(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		transport.SendError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}

	userUUID, err := ExtractUserID(r)
	if err != nil {
		transport.SendError(w, http.StatusUnauthorized, "Unauthorized")
		return
	}

	var totalGiven, totalReceived int
	var pointsGiven, pointsReceived int

	query := `
		SELECT 
			COUNT(*) FILTER (WHERE initiator_id = $1) as given,
			COUNT(*) FILTER (WHERE target_id = $1) as received,
			COALESCE(SUM(points) FILTER (WHERE initiator_id = $1), 0) as pts_given,
			COALESCE(SUM(points) FILTER (WHERE target_id = $1), 0) as pts_received
		FROM commitments
		WHERE status = 'ACKNOWLEDGED' AND (initiator_id = $1 OR target_id = $1)
	`
	err = h.db.QueryRowContext(r.Context(), query, userUUID).Scan(&totalGiven, &totalReceived, &pointsGiven, &pointsReceived)
	if err != nil {
		log.Printf("DB Query Error (GetProfileStats): %v", err)
		transport.SendError(w, http.StatusInternalServerError, "Internal server error")
		return
	}

	transport.WriteJSON(w, http.StatusOK, map[string]interface{}{
		"karma_score":            calculateKarmaScore(totalGiven+totalReceived, pointsGiven+pointsReceived),
		"total_favours_given":    totalGiven,
		"total_favours_received": totalReceived,
		"total_points_given":     pointsGiven,
		"total_points_received":  pointsReceived,
	})
}

// GetActivityGraph returns points comparison with top friends
func (h *FriendsHandler) GetActivityGraph(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		transport.SendError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}

	userUUID, err := ExtractUserID(r)
	if err != nil {
		transport.SendError(w, http.StatusUnauthorized, "Unauthorized")
		return
	}

	// Fetch top 5 friends based on total points exchanged
	query := `
		WITH friend_points AS (
			SELECT 
				CASE WHEN ur.user_a_id = $1 THEN ur.user_b_id ELSE ur.user_a_id END as friend_id,
				SUM(c.points) as total_points
			FROM user_relationships ur
			JOIN commitments c ON c.rel_id = ur.id
			WHERE (ur.user_a_id = $1 OR ur.user_b_id = $1) AND ur.status = 'ACCEPTED' AND c.status = 'ACKNOWLEDGED'
			GROUP BY friend_id
			ORDER BY total_points DESC
			LIMIT 5
		)
		SELECT u.name, fp.total_points
		FROM friend_points fp
		JOIN users u ON u.id = fp.friend_id
	`
	rows, err := h.db.QueryContext(r.Context(), query, userUUID)
	if err != nil {
		transport.SendError(w, http.StatusInternalServerError, "Internal server error")
		return
	}
	defer rows.Close()

	var results []map[string]interface{}
	for rows.Next() {
		var name string
		var points int
		if err := rows.Scan(&name, &points); err != nil {
			continue
		}
		results = append(results, map[string]interface{}{"name": name, "points": points})
	}

	transport.WriteJSON(w, http.StatusOK, results)
}
