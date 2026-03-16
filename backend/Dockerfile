# Build stage
FROM golang:1.25-alpine AS builder

WORKDIR /app

# Install build dependencies
RUN apk add --no-cache gcc musl-dev

COPY go.mod go.sum ./
RUN go mod download

COPY . .

# Build the binary with flags for a smaller, static binary
RUN go mod tidy && go mod verify

RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o main ./cmd/server

# Final stage
FROM alpine:latest

RUN apk add --no-cache ca-certificates tzdata

WORKDIR /app

# Copy the binary from builder
COPY --from=builder /app/main .

# Copy Firebase credentials (will be injected by CI if not exists)
# In production, we'll use a volume or secret injection
# COPY firebase-adminsdk.json .

EXPOSE 8080

CMD ["./main"]