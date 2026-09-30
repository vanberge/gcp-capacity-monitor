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

# ==============================================================================
# LOG-BASED METRICS
# ==============================================================================

# 1. Universal Stockouts Metric (All Services)
resource "google_logging_metric" "gcp_capacity_stockouts" {
  name        = "gcp_capacity_stockouts"
  description = "Universal metric tracking all GCP capacity stockouts across GKE, Compute Engine (GCE), and Cloud SQL"
  project     = var.project_id

  filter = <<EOT
(resource.type="k8s_pod" AND logName : "events" AND jsonPayload.reason="FailedScaleUp" AND jsonPayload.message=~"GCE out of resources")
OR
(logName : "cloudaudit.googleapis.com%2Factivity" AND (protoPayload.methodName:"compute.instances.insert" OR protoPayload.methodName:"compute.instances.start") AND severity="ERROR" AND (protoPayload.status.message="ZONE_RESOURCE_POOL_EXHAUSTED" OR protoPayload.status.message=~"does not have enough resources available" OR protoPayload.status.details.value.errorInfo.reason="stockout" OR protoPayload.status.details.value.errorInfo.reason="ZONE_RESOURCE_POOL_EXHAUSTED"))
OR
(resource.type="cloudsql_database" AND logName : "cloudaudit.googleapis.com%2Factivity" AND (protoPayload.methodName:"cloudsql.instances.create" OR protoPayload.methodName:"cloudsql.instances.update" OR protoPayload.methodName:"cloudsql.instances.restart" OR protoPayload.methodName:"cloudsql.instances.failover" OR protoPayload.methodName:"cloudsql.instances.clone") AND severity="ERROR" AND (protoPayload.status.code=111 OR protoPayload.status.code=8 OR protoPayload.status.message=~"(ZONE_RESOURCE_POOL_EXHAUSTED|resource pool exhausted|insufficient capacity|does not have enough resources available|The zone is currently out of capacity|stockout)" OR protoPayload.status.details.value.errorInfo.reason=~"(stockout|ZONE_RESOURCE_POOL_EXHAUSTED)"))
EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    labels {
      key         = "service_name"
      value_type  = "STRING"
      description = "Service name (compute.googleapis.com, cloudsql.googleapis.com, or k8s.io)"
    }
  }

  label_extractors = {
    "service_name" = "REGEXP_EXTRACT(protoPayload.serviceName, \"([a-z0-9.]+)\")"
  }
}

# 2. GKE Stockouts Metric
resource "google_logging_metric" "gke_stockouts" {
  name        = "gke_node_provisioning_stockouts"
  description = "Universal metric tracking GKE instance stockouts during node provisioning"
  project     = var.project_id

  filter = <<EOT
(resource.type="k8s_pod" AND logName : "events" AND jsonPayload.reason="FailedScaleUp" AND jsonPayload.message=~"GCE out of resources")
OR
(logName : "cloudaudit.googleapis.com%2Factivity" AND protoPayload.methodName:"compute.instances.insert" AND severity="ERROR" AND (protoPayload.status.message="ZONE_RESOURCE_POOL_EXHAUSTED" OR protoPayload.status.details.value.errorInfo.reason="stockout") AND (protoPayload.resourceName=~"/instances/gke-" OR protoPayload.resourceName=~"-nap-"))
EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }
}

# 3. GKE Node Provisioning Successes Metric
resource "google_logging_metric" "gke_provisioning_successes" {
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

# 4. GCE Instance Stockouts Metric
resource "google_logging_metric" "gce_stockouts" {
  name        = "gce_instance_stockouts"
  description = "Metric tracking regular Compute Engine (GCE) instance stockouts during creation and starts (excluding GKE nodes)"
  project     = var.project_id

  filter = <<EOT
logName : "cloudaudit.googleapis.com%2Factivity"
AND (protoPayload.methodName:"compute.instances.insert" OR protoPayload.methodName:"compute.instances.start")
AND severity="ERROR"
AND (protoPayload.status.message="ZONE_RESOURCE_POOL_EXHAUSTED" OR protoPayload.status.message=~"does not have enough resources available" OR protoPayload.status.details.value.errorInfo.reason="stockout" OR protoPayload.status.details.value.errorInfo.reason="ZONE_RESOURCE_POOL_EXHAUSTED")
AND NOT protoPayload.resourceName=~"/instances/gke-"
AND NOT protoPayload.resourceName=~"-nap-"
EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    labels {
      key         = "zone"
      value_type  = "STRING"
      description = "Zone where the stockout occurred"
    }
    labels {
      key         = "method"
      value_type  = "STRING"
      description = "Method: insert or start"
    }
  }

  label_extractors = {
    "zone"   = "EXTRACT(resource.labels.zone)"
    "method" = "REGEXP_EXTRACT(protoPayload.methodName, \".*\\.(insert|start)\")"
  }
}

# 5. GCE Instance Provisioning Successes Metric
resource "google_logging_metric" "gce_provisioning_successes" {
  name        = "gce_instance_provisioning_successes"
  description = "Metric tracking successful regular Compute Engine (GCE) instance creations (excluding GKE nodes)"
  project     = var.project_id

  filter = <<EOT
logName : "cloudaudit.googleapis.com%2Factivity"
AND protoPayload.methodName:"compute.instances.insert"
AND operation.last=true
AND NOT severity="ERROR"
AND NOT protoPayload.resourceName=~"/instances/gke-"
AND NOT protoPayload.resourceName=~"-nap-"
EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    labels {
      key         = "zone"
      value_type  = "STRING"
      description = "Zone where the instance was created"
    }
  }

  label_extractors = {
    "zone" = "EXTRACT(resource.labels.zone)"
  }
}

# 6. Cloud SQL Instance Stockouts Metric
resource "google_logging_metric" "cloudsql_stockouts" {
  name        = "cloudsql_instance_stockouts"
  description = "Metric tracking Cloud SQL database instance stockouts during creation, resize, restart, or failover"
  project     = var.project_id

  filter = <<EOT
resource.type="cloudsql_database"
AND logName : "cloudaudit.googleapis.com%2Factivity"
AND (protoPayload.methodName:"cloudsql.instances.create" OR protoPayload.methodName:"cloudsql.instances.update" OR protoPayload.methodName:"cloudsql.instances.restart" OR protoPayload.methodName:"cloudsql.instances.failover" OR protoPayload.methodName:"cloudsql.instances.clone")
AND severity="ERROR"
AND (protoPayload.status.code=111 OR protoPayload.status.code=8 OR protoPayload.status.message=~"(ZONE_RESOURCE_POOL_EXHAUSTED|resource pool exhausted|insufficient capacity|does not have enough resources available|The zone is currently out of capacity|stockout)" OR protoPayload.status.details.value.errorInfo.reason=~"(stockout|ZONE_RESOURCE_POOL_EXHAUSTED)")
EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    labels {
      key         = "region"
      value_type  = "STRING"
      description = "Region of the Cloud SQL instance"
    }
    labels {
      key         = "database_id"
      value_type  = "STRING"
      description = "Database instance ID"
    }
    labels {
      key         = "method"
      value_type  = "STRING"
      description = "Cloud SQL operation method"
    }
  }

  label_extractors = {
    "region"      = "EXTRACT(resource.labels.region)"
    "database_id" = "EXTRACT(resource.labels.database_id)"
    "method"      = "REGEXP_EXTRACT(protoPayload.methodName, \".*\\.(create|update|restart|failover|clone)\")"
  }
}

# 7. Cloud SQL Instance Provisioning Successes Metric
resource "google_logging_metric" "cloudsql_provisioning_successes" {
  name        = "cloudsql_instance_provisioning_successes"
  description = "Metric tracking successful Cloud SQL database creations and tier updates"
  project     = var.project_id

  filter = <<EOT
resource.type="cloudsql_database"
AND logName : "cloudaudit.googleapis.com%2Factivity"
AND (protoPayload.methodName:"cloudsql.instances.create" OR protoPayload.methodName:"cloudsql.instances.update")
AND operation.last=true
AND NOT severity="ERROR"
EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    labels {
      key         = "region"
      value_type  = "STRING"
      description = "Region of the Cloud SQL instance"
    }
    labels {
      key         = "database_id"
      value_type  = "STRING"
      description = "Database instance ID"
    }
    labels {
      key         = "method"
      value_type  = "STRING"
      description = "Operation method: create or update"
    }
  }

  label_extractors = {
    "region"      = "EXTRACT(resource.labels.region)"
    "database_id" = "EXTRACT(resource.labels.database_id)"
    "method"      = "REGEXP_EXTRACT(protoPayload.methodName, \".*\\.(create|update)\")"
  }
}

# ==============================================================================
# MONITORING DASHBOARDS
# ==============================================================================

# 1. Executive Roll-Up Dashboard
resource "google_monitoring_dashboard" "overview_dashboard" {
  project        = var.project_id
  dashboard_json = replace(file("${path.module}/../dashboards/dashboard-overview.json"), "$${PROJECT_ID}", var.project_id)

  depends_on = [
    google_logging_metric.gcp_capacity_stockouts,
    google_logging_metric.gke_stockouts,
    google_logging_metric.gke_provisioning_successes,
    google_logging_metric.gce_stockouts,
    google_logging_metric.gce_provisioning_successes,
    google_logging_metric.cloudsql_stockouts,
    google_logging_metric.cloudsql_provisioning_successes,
  ]
}

# 2. GKE Dedicated Dashboard
resource "google_monitoring_dashboard" "gke_dashboard" {
  project        = var.project_id
  dashboard_json = replace(file("${path.module}/../dashboards/dashboard-gke.json"), "$${PROJECT_ID}", var.project_id)

  depends_on = [
    google_logging_metric.gke_stockouts,
    google_logging_metric.gke_provisioning_successes,
  ]
}

# 3. GCE Dedicated Dashboard
resource "google_monitoring_dashboard" "gce_dashboard" {
  project        = var.project_id
  dashboard_json = replace(file("${path.module}/../dashboards/dashboard-gce.json"), "$${PROJECT_ID}", var.project_id)

  depends_on = [
    google_logging_metric.gce_stockouts,
    google_logging_metric.gce_provisioning_successes,
  ]
}

# 4. Cloud SQL Dedicated Dashboard
resource "google_monitoring_dashboard" "cloudsql_dashboard" {
  project        = var.project_id
  dashboard_json = replace(file("${path.module}/../dashboards/dashboard-cloudsql.json"), "$${PROJECT_ID}", var.project_id)

  depends_on = [
    google_logging_metric.cloudsql_stockouts,
    google_logging_metric.cloudsql_provisioning_successes,
  ]
}
