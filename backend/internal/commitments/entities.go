package commitments

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
)

// Broadcaster allows sending messages to all active clients without importing the main ws package
type Broadcaster interface {
	Broadcast(message []byte)
}

// EntitiesHandler handles entity-related HTTP endpoints
type EntitiesHandler struct {
	db          *sql.DB
	broadcaster Broadcaster
}

func NewEntitiesHandler(db *sql.DB, broadcaster Broadcaster) *EntitiesHandler {
	return &EntitiesHandler{db: db, broadcaster: broadcaster}
}

type EntityInfo struct {
	ID         string  `json:"id"`
	Name       string  `json:"name"`
	TotalScore int64   `json:"total_score"`
	UsersVotes int     `json:"users_votes"`
	AvgScore   float64 `json:"avg_score"`
}

// ListEntities returns all entities of the given type for autocomplete
func (h *EntitiesHandler) ListEntities(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	entityType := r.URL.Query().Get("type")
	if entityType == "" {
		entityType = "MATERIAL"
	}

	table := "materialistic_entities"
	if entityType == "EMOTIONAL" {
		table = "emotional_entities"
	}

	query := fmt.Sprintf(`
		SELECT id, name, total_score, users_votes
		FROM %s
		ORDER BY name ASC
	`, table)

	rows, err := h.db.QueryContext(r.Context(), query)
	if err != nil {
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	entities := []EntityInfo{}
	for rows.Next() {
		var e EntityInfo
		if err := rows.Scan(&e.ID, &e.Name, &e.TotalScore, &e.UsersVotes); err != nil {
			http.Error(w, "Internal server error", http.StatusInternalServerError)
			return
		}
		if e.UsersVotes > 0 {
			e.AvgScore = float64(e.TotalScore) / float64(e.UsersVotes)
		}
		entities = append(entities, e)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(entities)
}

// CreateEntity creates a new subgroup / entity manually
func (h *EntitiesHandler) CreateEntity(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req struct {
		Name   string  `json:"name"`
		Type   string  `json:"type"`
		Rating float64 `json:"rating"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	if req.Name == "" || (req.Type != "MATERIAL" && req.Type != "EMOTIONAL") {
		http.Error(w, "Name and valid type (MATERIAL/EMOTIONAL) are required", http.StatusBadRequest)
		return
	}

	table := "materialistic_entities"
	if req.Type == "EMOTIONAL" {
		table = "emotional_entities"
	}

	// Insert or do nothing if conflict, we'll return the ID
	// If a new entity, initialize its total_score and users_votes
	query := fmt.Sprintf(`
		INSERT INTO %s (name, total_score, users_votes) VALUES ($1, $2, 1)
		ON CONFLICT (name) DO UPDATE SET name = EXCLUDED.name
		RETURNING id, name, total_score, users_votes
	`, table)

	var e EntityInfo
	err := h.db.QueryRowContext(r.Context(), query, req.Name, req.Rating).Scan(&e.ID, &e.Name, &e.TotalScore, &e.UsersVotes)
	if err != nil {
		http.Error(w, "Database error", http.StatusInternalServerError)
		return
	}

	if e.UsersVotes > 0 {
		e.AvgScore = float64(e.TotalScore) / float64(e.UsersVotes)
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(e)

	// Broadcast the new entity to all active WebSocket clients
	if h.broadcaster != nil {
		payload, err := json.Marshal(map[string]interface{}{
			"type":   "new_entity",
			"entity": e,
			"category": req.Type, // "MATERIAL" or "EMOTIONAL"
		})
		if err == nil {
			h.broadcaster.Broadcast(payload)
		}
	}
}
