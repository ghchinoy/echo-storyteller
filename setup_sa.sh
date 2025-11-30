#!/bin/bash
#
# Service Account Setup Script for Echo Storyteller
#
# This script:
# 1. Enables required APIs (Vertex AI, Text-to-Speech).
# 2. Creates a dedicated Service Account for the application.
# 3. Assigns the necessary permissions (Vertex AI User, Logging Writer).
#

# Load env vars
if [ -f .env ]; then
  source .env
fi

PROJECT_ID=${GOOGLE_CLOUD_PROJECT:-${PROJECT_ID:-$(gcloud config get-value project)}}
SERVICE_NAME="${SERVICE_NAME:-echo-storyteller}"
SA_NAME="${SERVICE_NAME}-sa"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

echo "------------------------------------------------"
echo "🚀 Setting up Infrastructure for $SERVICE_NAME"
echo "   Project: $PROJECT_ID"
echo "   Service Account: $SA_EMAIL"
echo "------------------------------------------------"

# 0. Enable APIs
echo "🔌 Enabling required APIs..."
gcloud services enable \
  aiplatform.googleapis.com \
  texttospeech.googleapis.com \
  --project "$PROJECT_ID"

# 1. Create Service Account
if gcloud iam service-accounts describe "$SA_EMAIL" --project "$PROJECT_ID" >/dev/null 2>&1; then
  echo "✅ Service Account already exists."
else
  echo "Creating Service Account..."
  gcloud iam service-accounts create "$SA_NAME" \
    --display-name="Service Account for $SERVICE_NAME" \
    --project "$PROJECT_ID"
  echo "✅ Service Account created."
fi

# 2. Grant Roles
echo "Granting permissions..."

# Vertex AI User (for Gemini Text Generation)
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/aiplatform.user" \
    --condition=None --quiet

# Cloud Text-to-Speech Service Agent (Often not strictly needed if API enabled, but good practice for visibility)
# Note: TTS doesn't have a specific "User" data-plane role, but Vertex AI User covers the AI Platform parts.
# We add Service Usage Consumer to allow quota usage.
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/serviceusage.serviceUsageConsumer" \
    --condition=None --quiet

# Logging Writer (for Cloud Run logs)
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/logging.logWriter" \
    --condition=None --quiet

echo "------------------------------------------------"
echo "✅ Setup Complete!"
echo ""
echo "Next Steps:"
echo "1. Ensure .env has GOOGLE_CLOUD_PROJECT and GOOGLE_CLOUD_LOCATION set."
echo "2. Open 'deploy.sh'"
echo "3. Uncomment the line: ARGS+=( \"--service-account\" \"$SA_EMAIL\" )"
echo "4. Run ./deploy.sh"
echo "------------------------------------------------"
