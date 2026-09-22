#!/usr/bin/env bash
# ==============================================================================
# Deploy GKE ComputeClass Universal Monitoring Dashboard & Metrics
# Usage: ./deploy.sh [TARGET_PROJECT_ID]
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_PROJECT="${1:-$(gcloud config get-value project 2>/dev/null)}"

if [ -z "${TARGET_PROJECT}" ]; then
  echo "Error: TARGET_PROJECT is required. Run: ./deploy.sh <project-id>"
  exit 1
fi

echo "==> Deploying to Project: ${TARGET_PROJECT}"

export CLOUDSDK_METRICS_ENVIRONMENT="${CLOUDSDK_METRICS_ENVIRONMENT:+$CLOUDSDK_METRICS_ENVIRONMENT }datacloud.antigravity"

# 1. Create Universal Stockout Metric
echo "==> 1/3 Creating/Updating log metric: gke_node_provisioning_stockouts..."
if gcloud logging metrics describe gke_node_provisioning_stockouts --project="${TARGET_PROJECT}" >/dev/null 2>&1; then
  gcloud logging metrics update gke_node_provisioning_stockouts \
    --config-from-file="${SCRIPT_DIR}/metric-stockouts.yaml" \
    --project="${TARGET_PROJECT}"
else
  gcloud logging metrics create gke_node_provisioning_stockouts \
    --config-from-file="${SCRIPT_DIR}/metric-stockouts.yaml" \
    --project="${TARGET_PROJECT}"
fi

# 2. Create Universal Machine Family Successes Metric
echo "==> 2/3 Creating/Updating log metric: gke_node_provisioning_successes..."
if gcloud logging metrics describe gke_node_provisioning_successes --project="${TARGET_PROJECT}" >/dev/null 2>&1; then
  gcloud logging metrics update gke_node_provisioning_successes \
    --config-from-file="${SCRIPT_DIR}/metric-provisioning-successes.yaml" \
    --project="${TARGET_PROJECT}"
else
  gcloud logging metrics create gke_node_provisioning_successes \
    --config-from-file="${SCRIPT_DIR}/metric-provisioning-successes.yaml" \
    --project="${TARGET_PROJECT}"
fi

# 3. Create Monitoring Dashboard
echo "==> 3/3 Deploying Cloud Monitoring Dashboard..."
TMP_DASH_JSON=$(mktemp)
sed "s/\${PROJECT_ID}/${TARGET_PROJECT}/g" "${SCRIPT_DIR}/dashboard.json" > "${TMP_DASH_JSON}"

DASHBOARD_ID=$(gcloud monitoring dashboards create \
  --config-from-file="${TMP_DASH_JSON}" \
  --project="${TARGET_PROJECT}" \
  --format="value(name)")
rm -f "${TMP_DASH_JSON}"

echo ""
echo "=============================================================================="
echo " SUCCESS! Dashboard deployed."
echo " Dashboard Resource: ${DASHBOARD_ID}"
echo " Console Link: https://console.cloud.google.com/monitoring/dashboards/builder/${DASHBOARD_ID##*/}?project=${TARGET_PROJECT}"
echo "=============================================================================="
