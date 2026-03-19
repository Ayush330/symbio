package ws

import (
	"context"
	"encoding/json"
	"github.com/Ayush330/symbio/backend/internal/logger"

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
				logger.Error("WS Read Error", "userID", c.UserID, "error", err)
			}
			break
		}
		
		c.handleMessage(message)
	}
}

func (c *Client) handleMessage(raw []byte) {
	var msg WSMessage
	if err := json.Unmarshal(raw, &msg); err != nil {
		logger.Error("Error unmarshaling WS message", "error", err)
		return
	}

	userUUID, err := uuid.Parse(c.UserID)
	if err != nil {
		logger.Error("Invalid user ID in client", "userID", c.UserID, "error", err)
		return
	}

	ctx := context.Background()

	switch msg.Type {
	case "request_commitment":
		var req commitments.RequestCommitmentReq
		if err := json.Unmarshal(msg.Data, &req); err != nil {
			logger.Error("Invalid request_commitment data", "error", err)
			return
		}
		comm, err := c.CommitmentsService.RequestCommitment(ctx, userUUID, req)
		if err != nil {
			logger.Error("Failed to request commitment", "userID", c.UserID, "error", err)
		} else {
			// Notify the target user
			commBytes, _ := json.Marshal(comm)
			payload, _ := json.Marshal(WSMessage{
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
			logger.Error("Invalid accept_commitment data", "error", err)
			return
		}
		comm, err := c.CommitmentsService.AcceptCommitment(ctx, userUUID, req)
		if err != nil {
			logger.Error("Failed to accept commitment", "userID", c.UserID, "error", err)
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
		}

	case "deny_commitment":
		var req commitments.DenyCommitmentReq
		if err := json.Unmarshal(msg.Data, &req); err != nil {
			logger.Error("Invalid deny_commitment data", "error", err)
			return
		}
		comm, err := c.CommitmentsService.DenyCommitment(ctx, userUUID, req)
		if err != nil {
			logger.Error("Failed to deny commitment", "userID", c.UserID, "error", err)
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

	case "ping":
		// Silent acknowledgment to keep connection alive and clean up logs
		return

	default:
		logger.Warn("Unknown message type", "type", msg.Type, "userID", c.UserID)
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

			// Send each message in its own frame to avoid parsing issues on mobile
			err := c.Conn.WriteMessage(websocket.TextMessage, message)
			if err != nil {
				logger.Error("WS Write Error", "userID", c.UserID, "error", err)
				return
			}
			logger.Debug("WS: Frame delivered", "userID", c.UserID, "size", len(message))
		}
	}
}
