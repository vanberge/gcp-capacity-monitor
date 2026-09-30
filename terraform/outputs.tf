output "overview_dashboard_id" {
  description = "The ID of the Executive Overview Cloud Monitoring dashboard."
  value       = google_monitoring_dashboard.overview_dashboard.id
}

output "gke_dashboard_id" {
  description = "The ID of the GKE Capacity Cloud Monitoring dashboard."
  value       = google_monitoring_dashboard.gke_dashboard.id
}

output "gce_dashboard_id" {
  description = "The ID of the GCE Capacity Cloud Monitoring dashboard."
  value       = google_monitoring_dashboard.gce_dashboard.id
}

output "cloudsql_dashboard_id" {
  description = "The ID of the Cloud SQL Capacity Cloud Monitoring dashboard."
  value       = google_monitoring_dashboard.cloudsql_dashboard.id
}
