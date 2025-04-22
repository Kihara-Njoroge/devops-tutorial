output "namespace" {
  value = kubernetes_namespace.test_app.metadata[0].name
  description = "The Kubernetes namespace for the test application"
}

output "frontend_service" {
  value = kubernetes_service.frontend_service.metadata[0].name
  description = "The name of the frontend service"
}

output "backend_service" {
  value = kubernetes_service.backend_service.metadata[0].name
  description = "The name of the backend service"
}

output "database_service" {
  value = kubernetes_service.database_service.metadata[0].name
  description = "The name of the database service"
}
