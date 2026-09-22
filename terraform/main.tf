terraform {
  required_version = ">= 1.3"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.50"
    }
  }
}

provider "google" {
  project = var.project_id
}

# 1. Stockout Metric
resource "google_logging_metric" "stockouts" {
  name        = "gke_node_provisioning_stockouts"
  description = "Universal metric tracking GKE/GCE instance stockouts during node provisioning"
  project     = var.project_id

  filter = <<EOT
(resource.type="k8s_pod" AND logName : "events" AND jsonPayload.reason="FailedScaleUp" AND jsonPayload.message=~"GCE out of resources")
OR
(logName : "cloudaudit.googleapis.com%2Factivity" AND protoPayload.methodName:"compute.instances.insert" AND severity="ERROR" AND (protoPayload.status.message="ZONE_RESOURCE_POOL_EXHAUSTED" OR protoPayload.status.details.value.errorInfo.reason="stockout"))
EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }
}

# 2. Node Provisioning Successes Metric with machine_family label
resource "google_logging_metric" "provisioning_successes" {
  name        = "gke_node_provisioning_successes"
  description = "Universal metric tracking successful auto-provisioned GKE nodes across all clusters, labeled by machine family"
  project     = var.project_id

  filter = <<EOT
logName : "cloudaudit.googleapis.com%2Factivity"
protoPayload.methodName:"compute.instances.insert"
operation.last=true
NOT severity="ERROR"
protoPayload.resourceName=~"-nap-[a-z0-9]+-"
EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    labels {
      key         = "machine_family"
      value_type  = "STRING"
      description = "Machine family (e.g. n2, e2, n4, n2d, c3d, t2d)"
    }
  }

  label_extractors = {
    "machine_family" = "REGEXP_EXTRACT(protoPayload.resourceName, \".*-nap-([a-z0-9]+)-.*\")"
  }
}

# 3. Cloud Monitoring Dashboard
resource "google_monitoring_dashboard" "computeclass_dashboard" {
  project        = var.project_id
  dashboard_json = replace(file("${path.module}/../dashboard.json"), "$${PROJECT_ID}", var.project_id)

  depends_on = [
    google_logging_metric.stockouts,
    google_logging_metric.provisioning_successes,
  ]
}
