output "dashboard_id" {
  description = "The ID of the deployed Cloud Monitoring dashboard."
  value       = google_monitoring_dashboard.computeclass_dashboard.id
}
