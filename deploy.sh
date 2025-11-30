#!/bin/bash
#
# Echo Storyteller Deployment Script
#
# This script deploys the "Echo Storyteller" application to Google Cloud Run.
# It handles loading configuration from a local .env file, building the Flutter web app,
# and executing the gcloud deploy command.
#
# Usage:
#   ./deploy.sh
#
# Configuration (.env):
#   Required:
#     GOOGLE_CLOUD_PROJECT - GCP Project ID
#     GOOGLE_CLOUD_LOCATION - Vertex AI Region (e.g., us-central1)
#
#   Optional:
#     REGION               - Cloud Run Region (Defaults to 'us-central1')
#     SERVICE_NAME         - Cloud Run Service Name (Defaults to 'echo-storyteller')
#

# Load environment variables from .env
if [ -f .env ]; then
  echo "Loading configuration from .env..."
  set -o allexport
  source .env
  set +o allexport
else
  echo "Error: .env file not found. Please create one with the required variables."
  exit 1
fi

# 1. Resolve Project ID
if [ -n "$GOOGLE_CLOUD_PROJECT" ]; then
  PROJECT_ID="$GOOGLE_CLOUD_PROJECT"
elif [ -z "$PROJECT_ID" ]; then
  PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
  if [ -z "$PROJECT_ID" ]; then
    echo "Error: GOOGLE_CLOUD_PROJECT or PROJECT_ID not found in .env and no default project set in gcloud."
    exit 1
  fi
fi
echo "Using Google Cloud Project: $PROJECT_ID"

# 2. Resolve Location (Required for Vertex AI)
if [ -z "$GOOGLE_CLOUD_LOCATION" ]; then
  GOOGLE_CLOUD_LOCATION="us-central1"
  echo "Using default Vertex AI location: $GOOGLE_CLOUD_LOCATION"
fi

# 3. Set Defaults for Region and Service Name
REGION="${REGION:-us-central1}"
SERVICE_NAME="${SERVICE_NAME:-echo-storyteller}"

# 4. Build Frontend
echo "🎨 Building Frontend (Flutter Web) for deployment..."
(cd frontend && flutter clean && flutter pub get && flutter build web)
if [ $? -ne 0 ]; then
  echo "Error: Flutter build failed."
  exit 1
fi

# 5. Deploy
# Resolve Service Account
# We highly recommend using the dedicated SA created by setup_sa.sh
SA_NAME="${SERVICE_NAME}-sa"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

echo "Deploying $SERVICE_NAME to $REGION in project $PROJECT_ID..."
echo "Vertex AI Location: $GOOGLE_CLOUD_LOCATION"
echo "Service Account: $SA_EMAIL"

ARGS=(
  "$SERVICE_NAME"
  "--source" "."
  "--project" "$PROJECT_ID"
  "--region" "$REGION"
  "--allow-unauthenticated"
  "--set-env-vars" "GOOGLE_CLOUD_PROJECT=$PROJECT_ID,GOOGLE_CLOUD_LOCATION=$GOOGLE_CLOUD_LOCATION"
)

# Check if SA exists, if so, use it
if gcloud iam service-accounts describe "$SA_EMAIL" --project "$PROJECT_ID" >/dev/null 2>&1; then
  ARGS+=( "--service-account" "$SA_EMAIL" )
  echo "✅ Using Service Account: $SA_EMAIL"
else
  echo "⚠️  Service Account $SA_EMAIL not found. Using default Compute Engine SA."
  echo "   Run ./setup_sa.sh to create the dedicated SA with correct permissions."
fi

gcloud run deploy "${ARGS[@]}"
