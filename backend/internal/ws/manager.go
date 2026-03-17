package ws

import "log"

type Envelope struct{
	TargetID string // The UserId we want to reach
	Payload []byte // The actual data (JSON)
}

type Manager struct {
	Clients    map[*Client]bool
	Broadcast  chan []byte
	Message chan Envelope
	Register   chan *Client
	Unregister chan *Client
}

func NewManager() *Manager {
	return &Manager{
		Broadcast:  make(chan []byte),
		Message: make(chan Envelope),
		Register:   make(chan *Client),
		Unregister: make(chan *Client),
		Clients:    make(map[*Client]bool),
	}
}

func (m *Manager) Run() {
	for {
		select {
		case client := <-m.Register:
			m.Clients[client] = true
			log.Printf("Client %s registered", client.UserID)
		case client := <-m.Unregister:
			if _, ok := m.Clients[client]; ok {
				delete(m.Clients, client)
				close(client.Send)
				log.Printf("Client %s unregistered", client.UserID)
			}
		case message := <-m.Message:
			// Send only to the required players
			matchFound := false
			for client := range m.Clients {
				if client.UserID == message.TargetID {
					select {
					case client.Send <- message.Payload:
						matchFound = true
					default:
						close(client.Send)
						delete(m.Clients, client)
					}
				}
			}
			if !matchFound {
				log.Printf("WS: No active clients found for UserID %s (Total clients: %d)", message.TargetID, len(m.Clients))
			} else {
				log.Printf("WS: Message delivered to UserID %s", message.TargetID)
			}
		case message := <-m.Broadcast:
			for client := range m.Clients {
				select {
				case client.Send <- message:
				default:
					close(client.Send)
					delete(m.Clients, client)
				}
			}
		}
	}
}
