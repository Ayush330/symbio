# Symbio Server Architecture Overview (WS-Centric)

Symbio is built as a highly-trust, real-time social integrity ledger. The backend uses **REST for Authentication** and **WebSockets for all business actions**.

## Core Architectural Patterns

### 1. Unified WebSocket Communication
Except for the initial authentication (Login/Signup), all client-to-server and server-to-client communication happens over a single persistent WebSocket connection.
- **Bi-directional**: The client sends commands (e.g., `request_commitment`) and the server pushes updates (e.g., `commitment_received`, `score_updated`).
- **Message Protocol**: All messages are JSON-encoded with a `type` and `data` payload.

### 2. Transactional Outbox Pattern
To ensure atomicity between database updates and event notifications (Kafka), Symbio uses an **Outbox Pattern**.
- **The Flow**: When a business action occurs via WebSocket, the service performs the DB update AND inserts an event into the `outbox_events` table within a single transaction.
- **The Relay**: A background worker publishes events to Kafka, ensuring reliability.

## Core Modules

| Module | Responsibility |
| :--- | :--- |
| **`auth`** | **REST-based**: User registration, login, and JWT issuance. |
| **`commitments`** | **WS-based**: All ledger interactions (request, accept, deny). |
| **`ws`** | **Core Transport**: Manages persistent connections and routes incoming messages to services. |
| **`outbox`** | Background reliable event dispatching via the Outbox Relay. |

## Data Flow Diagram

```mermaid
graph TD
    Client[Flutter App] -->|HTTPS POST| Auth[Auth Service]
    Auth -->|Token| Client
    
    Client <-->|WS (JSON Messages)| WSManager[WebSocket Manager]
    WSManager -->|Route Message| Service[Service Layer]
    Service -->|Tx| DB[(Postgres DB)]
    Service -->|Tx| Outbox[(Outbox Table)]
    
    Relay[Outbox Relay] -->|Poll| Outbox
    Relay -->|Publish| Kafka[Kafka]
```

---

# Postman Test Plan (WS-Centric)

## 1. REST Authentication (Initial Setup)
Ensure the server is running on `http://localhost:8080`.

### **A. Signup**
- **Method**: `POST`
- **URL**: `{{baseUrl}}/signup`
- **Body (JSON)**: `{"email": "test@example.com", "password": "password123", "name": "Test User"}`
- **Expected**: `201 Created` with a `token`.

### **B. Login**
- **Method**: `POST`
- **URL**: `{{baseUrl}}/login`
- **Body (JSON)**: `{"email": "test@example.com", "password": "password123"}`
- **Expected**: `200 OK` with a `token`. **Use this token for WS connection.**

## 2. WebSocket Actions
Open a **WebSocket Request** in Postman to `ws://localhost:8080/ws?token={{jwt_token}}`.

### **A. Connection**
- **Expected**: Connection opened and "Client registered" logged on server.

### **B. Request Commitment**
- **Message Body**:
  ```json
  {
    "type": "request_commitment",
    "data": {
      "target_user_id": "UUID_OF_OTHER_USER",
      "entity_name": "Weekly Gym Session",
      "entity_type": "habit",
      "rating": 50
    }
  }
  ```
- **Expected**: Server processes the request and responds with a confirmation/ack message.

### **C. Accept Commitment**
- **Message Body**:
  ```json
  {
    "type": "accept_commitment",
    "data": {
      "commitment_id": "UUID_OF_COMMITMENT"
    }
  }
  ```
- **Expected**: Server updates ledger and broadcasts status change.
