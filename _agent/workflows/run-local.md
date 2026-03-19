---
description: how to run the application locally
---

To run the Symbio (Kizuna) application on your local machine, follow these steps:

### 1. Prerequisites
- Ensure you have **Docker** and **Docker Compose** installed.
- Ensure you have **Flutter** installed for the frontend.
- Ensure you have a `.env` file in the root directory with your `GEMINI_API_KEY`.

### 2. Start the Backend Infrastructure
Run the following command in the root directory to start Postgres, Redis, and the Go API:

```bash
docker compose up --build -d
```

> [!NOTE]
> The API will be available at `http://localhost:8080`. If you are running on a physical device or an Android emulator, you MUST update the `baseUrl` in `frontend/lib/main.dart` to your MacBook's private IP (currently set to `192.168.1.6`).

### 3. Start the Frontend (Flutter)
Navigate to the `frontend` directory and run the app:

```bash
cd frontend
flutter run
```

### 4. Verification
- **Health Check**: Visit `http://localhost:8080/health` in your browser. It should return `OK`.
- **Database**: The schema will automatically migrate on startup.
- **Logs**: You can view the backend logs using `docker compose logs -f api`.

### Troubleshooting
If you encounter database connection issues, ensure no other service is using port `5432` or `6379`.
