# Build Stage: Go Backend
FROM golang:1.25-bookworm as builder

WORKDIR /app

# Copy backend code
COPY backend/ ./backend/

# Build Go Server
WORKDIR /app/backend
# Download dependencies
RUN go mod download
RUN go mod tidy
# Build the binary
RUN go build -o server main.go

# Runtime Stage
FROM debian:bookworm-slim

WORKDIR /app

# Install CA certificates for external API calls (Gemini, Google TTS)
RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*

# Copy built backend from builder to /app/backend/server
# We preserve the directory structure so that relative paths (like ../frontend) work as expected
COPY --from=builder /app/backend/server /app/backend/server

# Copy Frontend Assets
# The Go server expects to find them at "../frontend/build/web" relative to the working directory
COPY frontend/build/web /app/frontend/build/web

# Environment Variables
ENV PORT=8080

# Run Server from the backend directory so relative paths work
WORKDIR /app/backend
CMD ["./server"]
