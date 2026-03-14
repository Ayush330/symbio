package ws

import (
	"context"
	"encoding/json"
	"log"

	"github.com/Ayush330/symbio/backend/internal/commitments"
	"github.com/google/uuid"
	"github.com/gorilla/websocket"
)

type Client struct {
	Manager            *Manager
	CommitmentsService commitments.Service
	Conn               *websocket.Conn
	Send               chan []byte
	UserID             string
}

type WSMessage struct {
	Type string          `json:"type"`
	Data json.RawMessage `json:"data"`
}

func (c *Client) ReadPump() {
	defer func() {
		c.Manager.Unregister <- c
		c.Conn.Close()
	}()

	for {
		_, message, err := c.Conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				log.Printf("error: %v", err)
			}
			break
		}
		
		c.handleMessage(message)
	}
}

func (c *Client) handleMessage(raw []byte) {
	var msg WSMessage
	if err := json.Unmarshal(raw, &msg); err != nil {
		log.Printf("Error unmarshaling WS message: %v", err)
		return
	}

	userUUID, err := uuid.Parse(c.UserID)
	if err != nil {
		log.Printf("Invalid user ID in client: %v", err)
		return
	}

	ctx := context.Background()

	switch msg.Type {
	case "request_commitment":
		var req commitments.RequestCommitmentReq
		if err := json.Unmarshal(msg.Data, &req); err != nil {
			log.Printf("Invalid request_commitment data: %v", err)
			return
		}
		comm, err := c.CommitmentsService.RequestCommitment(ctx, userUUID, req)
		if err != nil {
			log.Printf("Failed to request commitment: %v", err)
		} else {
			// Notify the target user
			payload, _ := json.Marshal(WSMessage{
				Type: "commitment_requested",
				Data: msg.Data, // Original request data or marshaled comm
			})
			// Overwrite Data with the actual Commitment object for better client-side info
			commBytes, _ := json.Marshal(comm)
			payload, _ = json.Marshal(WSMessage{
				Type: "commitment_requested",
				Data: commBytes,
			})
			c.Manager.Message <- Envelope{
				TargetID: req.TargetUserID,
				Payload:  payload,
			}
		}

	case "accept_commitment":
		var req commitments.AcceptCommitmentReq
		if err := json.Unmarshal(msg.Data, &req); err != nil {
			log.Printf("Invalid accept_commitment data: %v", err)
			return
		}
		comm, err := c.CommitmentsService.AcceptCommitment(ctx, userUUID, req)
		if err != nil {
			log.Printf("Failed to accept commitment: %v", err)
		} else {
			// Notify both parties of the state change
			commBytes, _ := json.Marshal(comm)
			payload, _ := json.Marshal(WSMessage{
				Type: "commitment_accepted",
				Data: commBytes,
			})

			// Notify Initiator
			c.Manager.Message <- Envelope{
				TargetID: comm.InitiatorID.String(),
				Payload:  payload,
			}
			// Notify Accepter (other clients of same user)
			c.Manager.Message <- Envelope{
				TargetID: c.UserID,
				Payload:  payload,
			}

			// GLOBAL BROADCAST: Notify all users about the new entity rating
			broadcastPayload, _ := json.Marshal(WSMessage{
				Type: "entity_rating_updated",
				Data: commBytes,
			})
			c.Manager.Broadcast <- broadcastPayload
		}

	case "deny_commitment":
		var req commitments.DenyCommitmentReq
		if err := json.Unmarshal(msg.Data, &req); err != nil {
			log.Printf("Invalid deny_commitment data: %v", err)
			return
		}
		comm, err := c.CommitmentsService.DenyCommitment(ctx, userUUID, req)
		if err != nil {
			log.Printf("Failed to deny commitment: %v", err)
		} else {
			// Notify the initiator
			commBytes, _ := json.Marshal(comm)
			payload, _ := json.Marshal(WSMessage{
				Type: "commitment_denied",
				Data: commBytes,
			})
			c.Manager.Message <- Envelope{
				TargetID: comm.InitiatorID.String(),
				Payload:  payload,
			}
		}

	case "rate_entity":
		// Standalone rating change for an existing entity
		type RateEntityReq struct {
			EntityID   string `json:"entity_id"`
			EntityType string `json:"entity_type"`
			Rating     int    `json:"rating"`
		}
		var req RateEntityReq
		if err := json.Unmarshal(msg.Data, &req); err != nil {
			log.Printf("Invalid rate_entity data: %v", err)
			return
		}

		entityID, err := uuid.Parse(req.EntityID)
		if err != nil {
			log.Printf("Invalid entity ID: %v", err)
			return
		}

		entityType := commitments.EntityType(req.EntityType)
		tx, err := c.CommitmentsService.BeginTx(ctx)
		if err != nil {
			log.Printf("Failed to begin tx for rating: %v", err)
			return
		}
		defer tx.Rollback()

		avgScore, err := c.CommitmentsService.UpdateEntityRating(ctx, tx, entityType, entityID, req.Rating)
		if err != nil {
			log.Printf("Failed to update entity rating: %v", err)
			return
		}
		tx.Commit()

		// Broadcast the updated rating to all connected users
		ratingUpdate := map[string]interface{}{
			"entity_id":        req.EntityID,
			"entity_type":      req.EntityType,
			"reliability_score": avgScore,
		}
		ratingBytes, _ := json.Marshal(ratingUpdate)
		broadcastPayload, _ := json.Marshal(WSMessage{
			Type: "entity_rating_updated",
			Data: ratingBytes,
		})
		c.Manager.Broadcast <- broadcastPayload

	default:
		log.Printf("Unknown message type: %s", msg.Type)
	}
}

func (c *Client) WritePump() {
	defer func() {
		c.Conn.Close()
	}()

	for {
		select {
		case message, ok := <-c.Send:
			if !ok {
				// The manager closed the channel.
				c.Conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}

			w, err := c.Conn.NextWriter(websocket.TextMessage)
			if err != nil {
				return
			}
			w.Write(message)

			// Add queued chat messages to the current websocket message.
			n := len(c.Send)
			for i := 0; i < n; i++ {
				w.Write([]byte{'\n'})
				w.Write(<-c.Send)
			}

			if err := w.Close(); err != nil {
				return
			}
		}
	}
}
