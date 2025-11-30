#!/bin/bash
#
# Project Echo: Development Script
#
# Usage:
#   ./dev.sh [--quick]
#

# Load environment variables from .env
if [ -f .env ]; then
  echo "Loading configuration from .env..."
  set -o allexport
  source .env
  set +o allexport
else
  echo "Notice: .env file not found."
fi

# 1. Frontend Build (Flutter)
if [[ "$*" == *"--quick"* ]]; then
  echo "------------------------------------------------"
  echo "⚡ Skipping Frontend build (--quick selected)"
else
  echo "------------------------------------------------"
  echo "🎨 Building Frontend (Flutter Web)..."
  # Using flutter run -d chrome is for hot reload, but for full integration test we build web.
  # For dev convenience, maybe we want to run backend and let user run flutter separately?
  # But strictly following the 'build and serve' model:
  (cd frontend && flutter build web)
  if [ $? -ne 0 ]; then
    echo "Error: Flutter build failed."
    exit 1
  fi
fi

# 2. Backend Build & Run (Go)
echo "------------------------------------------------"
echo "📡 Building and Starting Echo Server..."
cd backend
go build -o server
if [ $? -eq 0 ]; then
  port="${PORT:-8080}"
  echo "✅ Server starting on port $port..."
  echo "   - Web App: http://localhost:$port"
  echo "   - WS:      ws://localhost:$port/ws"
  ./server
else
  echo "❌ Backend build failed."
  exit 1
fi