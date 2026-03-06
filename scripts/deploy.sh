#!/usr/bin/env bash
set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────────
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
REGION="us-central1"
SERVICE_NAME="clutch"
REPO_NAME="clutch"
IMAGE="$REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/$SERVICE_NAME"

# Repo root (one level up from scripts/)
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Load env vars from .env if it exists
ENV_FILE="$REPO_ROOT/backend/.env"
if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: $ENV_FILE not found. Create it with your API keys."
  exit 1
fi

echo "==> Project:  $PROJECT_ID"
echo "==> Region:   $REGION"
echo "==> Service:  $SERVICE_NAME"
echo "==> Image:    $IMAGE"
echo ""

# ── Enable required APIs ──────────────────────────────────────────────────────
echo "==> Enabling required GCP APIs..."
gcloud services enable \
  artifactregistry.googleapis.com \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  --project="$PROJECT_ID" --quiet

# ── Create Artifact Registry repo (if needed) ────────────────────────────────
echo "==> Creating Artifact Registry repo (if needed)..."
gcloud artifacts repositories describe "$REPO_NAME" \
  --location="$REGION" --project="$PROJECT_ID" 2>/dev/null \
  || gcloud artifacts repositories create "$REPO_NAME" \
    --repository-format=docker \
    --location="$REGION" \
    --project="$PROJECT_ID" \
    --description="Clutch container images"

# ── Build & push image via Cloud Build (no local Docker needed) ──────────────
echo "==> Building image with Cloud Build..."
gcloud builds submit "$REPO_ROOT" \
  --tag="$IMAGE" \
  --project="$PROJECT_ID" \
  --quiet

# ── Read env vars for Cloud Run ──────────────────────────────────────────────
# Extract key=value pairs, skip comments and blank lines
ENV_VARS=""
while IFS= read -r line; do
  # Skip comments and empty lines
  [[ -z "$line" || "$line" =~ ^# ]] && continue
  key="${line%%=*}"
  value="${line#*=}"
  # Only include API keys and search config
  case "$key" in
    GOOGLE_API_KEY|YOUTUBE_API_KEY|GOOGLE_SEARCH_API_KEY|GOOGLE_SEARCH_CX)
      if [ -n "$ENV_VARS" ]; then
        ENV_VARS="$ENV_VARS,$key=$value"
      else
        ENV_VARS="$key=$value"
      fi
      ;;
  esac
done < "$ENV_FILE"

# ── Deploy to Cloud Run ──────────────────────────────────────────────────────
echo "==> Deploying to Cloud Run..."
gcloud run deploy "$SERVICE_NAME" \
  --image="$IMAGE" \
  --region="$REGION" \
  --project="$PROJECT_ID" \
  --platform=managed \
  --port=8080 \
  --min-instances=1 \
  --max-instances=10 \
  --memory=512Mi \
  --cpu=1 \
  --timeout=3600 \
  --session-affinity \
  --set-env-vars="$ENV_VARS" \
  --allow-unauthenticated \
  --quiet

# ── Print service URL ────────────────────────────────────────────────────────
echo ""
echo "==> Deployment complete!"
SERVICE_URL=$(gcloud run services describe "$SERVICE_NAME" \
  --region="$REGION" --project="$PROJECT_ID" \
  --format="value(status.url)")
echo "==> Service URL: $SERVICE_URL"
echo ""
echo "Open $SERVICE_URL in your browser to use Clutch."
