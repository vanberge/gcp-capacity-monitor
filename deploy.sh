#!/usr/bin/env bash
# ==============================================================================
# Deploy GCP Multi-Service Capacity & Stockout Monitoring (GCE, GKE, Cloud SQL)
# Usage: ./deploy.sh [TARGET_PROJECT_ID]
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_PROJECT="${1:-$(gcloud config get-value project 2>/dev/null)}"

if [ -z "${TARGET_PROJECT}" ]; then
  echo "Error: TARGET_PROJECT is required. Run: ./deploy.sh <project-id>"
  exit 1
fi

echo "=============================================================================="
echo " Deploying GCP Capacity & Stockout Monitoring to Project: ${TARGET_PROJECT}"
echo " Services covered: GKE (Kubernetes), GCE (Compute Engine), Cloud SQL (Databases)"
echo "=============================================================================="

export CLOUDSDK_METRICS_ENVIRONMENT="${CLOUDSDK_METRICS_ENVIRONMENT:+$CLOUDSDK_METRICS_ENVIRONMENT }datacloud.antigravity"

# Helper function to deploy/update a log metric
deploy_metric() {
  local metric_name="$1"
  local config_file="$2"
  echo "--> Metric: ${metric_name}..."
  if gcloud logging metrics describe "${metric_name}" --project="${TARGET_PROJECT}" >/dev/null 2>&1; then
    gcloud logging metrics update "${metric_name}" \
      --config-from-file="${config_file}" \
      --project="${TARGET_PROJECT}" >/dev/null
    echo "    ✓ Updated existing metric"
  else
    gcloud logging metrics create "${metric_name}" \
      --config-from-file="${config_file}" \
      --project="${TARGET_PROJECT}" >/dev/null
    echo "    ✓ Created new metric"
  fi
}

# Helper function to deploy a monitoring dashboard
deploy_dashboard() {
  local title="$1"
  local json_file="$2"
  echo "--> Dashboard: ${title}..." >&2
  local tmp_json
  tmp_json=$(mktemp)
  sed "s/\${PROJECT_ID}/${TARGET_PROJECT}/g" "${json_file}" > "${tmp_json}"

  local dashboard_id
  dashboard_id=$(gcloud monitoring dashboards create \
    --config-from-file="${tmp_json}" \
    --project="${TARGET_PROJECT}" \
    --format="value(name)")
  rm -f "${tmp_json}"
  local clean_id="${dashboard_id##*/}"
  echo "    ✓ Deployed (${clean_id})" >&2
  echo "${clean_id}"
}

echo ""
echo "[Step 1/2] Creating/Updating Log-Based Capacity Metrics..."
deploy_metric "gcp_capacity_stockouts" "${SCRIPT_DIR}/metrics/metric-gcp-stockouts.yaml"
deploy_metric "gke_node_provisioning_stockouts" "${SCRIPT_DIR}/metrics/metric-gke-stockouts.yaml"
deploy_metric "gke_node_provisioning_successes" "${SCRIPT_DIR}/metrics/metric-gke-provisioning-successes.yaml"
deploy_metric "gce_instance_stockouts" "${SCRIPT_DIR}/metrics/metric-gce-stockouts.yaml"
deploy_metric "gce_instance_provisioning_successes" "${SCRIPT_DIR}/metrics/metric-gce-provisioning-successes.yaml"
deploy_metric "cloudsql_instance_stockouts" "${SCRIPT_DIR}/metrics/metric-cloudsql-stockouts.yaml"
deploy_metric "cloudsql_instance_provisioning_successes" "${SCRIPT_DIR}/metrics/metric-cloudsql-provisioning-successes.yaml"

echo ""
echo "[Step 2/2] Deploying Cloud Monitoring Dashboards..."
OVERVIEW_ID=$(deploy_dashboard "Executive Overview" "${SCRIPT_DIR}/dashboards/dashboard-overview.json")
GKE_ID=$(deploy_dashboard "GKE Capacity & Stockouts" "${SCRIPT_DIR}/dashboards/dashboard-gke.json")
GCE_ID=$(deploy_dashboard "GCE Capacity & Stockouts" "${SCRIPT_DIR}/dashboards/dashboard-gce.json")
CLOUDSQL_ID=$(deploy_dashboard "Cloud SQL Capacity & Stockouts" "${SCRIPT_DIR}/dashboards/dashboard-cloudsql.json")

echo ""
echo "=============================================================================="
echo " SUCCESS! All Log Metrics & Custom Dashboards Deployed Successfully."
echo " Project: ${TARGET_PROJECT}"
echo "------------------------------------------------------------------------------"
echo " 1. Executive Roll-Up Dashboard:"
echo "    https://console.cloud.google.com/monitoring/dashboards/builder/${OVERVIEW_ID}?project=${TARGET_PROJECT}"
echo ""
echo " 2. GKE Dedicated Dashboard:"
echo "    https://console.cloud.google.com/monitoring/dashboards/builder/${GKE_ID}?project=${TARGET_PROJECT}"
echo ""
echo " 3. GCE Compute Engine Dedicated Dashboard:"
echo "    https://console.cloud.google.com/monitoring/dashboards/builder/${GCE_ID}?project=${TARGET_PROJECT}"
echo ""
echo " 4. Cloud SQL Database Dedicated Dashboard:"
echo "    https://console.cloud.google.com/monitoring/dashboards/builder/${CLOUDSQL_ID}?project=${TARGET_PROJECT}"
echo "=============================================================================="
