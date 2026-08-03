output "namespace" {
  description = "Неймспейс, у якому встановлено Argo CD"
  value       = kubernetes_namespace.argocd.metadata[0].name
}

output "release_name" {
  description = "Ім'я Helm-релізу Argo CD"
  value       = helm_release.argocd.name
}

output "server_service_name" {
  description = "Ім'я Service вебінтерфейсу Argo CD"
  value       = "${var.release_name}-server"
}

output "application_name" {
  description = "Ім'я створеного Argo CD Application"
  value       = var.application_name
}

output "destination_namespace" {
  description = "Неймспейс, у який Argo CD розгортає застосунок"
  value       = var.destination_namespace
}

output "url_command" {
  description = "Команда, що друкує зовнішній URL Argo CD"
  value       = "kubectl get svc ${var.release_name}-server -n ${var.namespace} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
}

output "password_command" {
  description = "Команда, що друкує початковий пароль admin (Argo CD генерує його сам при першій установці)"
  value       = "kubectl -n ${var.namespace} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}

output "port_forward_command" {
  description = "Доступ до UI без LoadBalancer"
  value       = "kubectl port-forward svc/${var.release_name}-server 8081:80 -n ${var.namespace}"
}
