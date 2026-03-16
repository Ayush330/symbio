# Symbio Flutter Architecture Overview

This document provides a high-level overview of the client-side architecture of the Symbio app. It is designed to help you understand the flow of data and the structure of the code without needing to dive into every detail.

## Core Philosophical Principles
- **Clean Architecture**: Separation of concerns into layers (Presentation, Data, Core).
- **Reactive State Management**: Using the BLoC (Business Logic Component) pattern to handle UI state changes.
- **Single Source of Truth**: Repositories manage data from local and remote sources.

---

## Folder Structure (`lib/`)

### 1. `core/` (The Infrastructure)
Contains low-level utilities and external integrations that don't belong to a specific feature.
- **`api/`**: HTTP client configuration (using `Dio`). Handles base URLs, interceptors (for auth tokens), and error handling.
- **`websocket/`**: Real-time communication logic. Manages connections, subscriptions, and message parsing.
- **`theme/`**: Global styles, colors, and typography (Dark Mode focus).
- **`services/`**: Independent system-level services like `NotificationService`.

### 2. `data/` (The Truth)
Handles data fetching and business entities.
- **`models/`**: Data classes (DTOs) that represent the structures returned by the backend.
- **`repositories/`**: The bridge between the UI and data sources. They coordinate fetching data from the API or WebSocket and converting them into high-level models the UI uses.

### 3. `presentation/` (The UI)
Everything the user sees and interacts with.
- **`blocs/`**: Business Logic Components. They receive **Events** (e.g., "User clicked login") and emit **States** (e.g., "Loading", "Error", "Success"). This is where the app's "brain" lives.
- **`screens/`**: Full-page layouts (Dashboard, Login, Friends).
- **`widgets/`**: Reusable UI components (custom buttons, cards, list items).

---

## Data Flow: How it works

1.  **User Interaction**: A user clicks a button on a **Screen**.
2.  **Event Dispatch**: The Screen sends an **Event** to a **Bloc**.
3.  **Repository Call**: The Bloc asks a **Repository** for data (e.g., "Fetch friends list").
4.  **Network Request**: The Repository uses the **API Client** (HTTP) or **WebSocket Client** to get raw data from the server.
5.  **State Update**: Once the data arrives, the Bloc emits a new **State** (e.g., `FriendsLoaded`).
6.  **UI Rebuild**: The UI (using a `BlocBuilder`) hears the new state and automatically rebuilds the screen with the new data.

---

## Key Technologies
- **Flutter**: The UI framework.
- **BLoC/Cubit**: State management.
- **Dio**: HTTP networking.
- **WebSockets**: Real-time updates for "Double-Handshake" and dashboard sync.
- **Firebase**: Push notifications.
