output "namespace" {
  description = "Неймспейс, у якому встановлено Jenkins"
  value       = kubernetes_namespace.jenkins.metadata[0].name
}

output "release_name" {
  description = "Ім'я Helm-релізу Jenkins"
  value       = helm_release.jenkins.name
}

output "service_name" {
  description = "Ім'я Service контролера Jenkins"
  value       = var.release_name
}

output "job_name" {
  description = "Ім'я створеної pipeline-джоби"
  value       = var.job_name
}

output "admin_username" {
  description = "Логін адміністратора Jenkins"
  value       = var.admin_username
}

output "agent_role_arn" {
  description = "ARN IAM-ролі агента (IRSA) — з нею Kaniko пушить образи в ECR"
  value       = aws_iam_role.agent.arn
}

output "url_command" {
  description = "Команда, що друкує зовнішній URL Jenkins"
  value       = "kubectl get svc ${var.release_name} -n ${var.namespace} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
}

output "password_command" {
  description = "Команда, що друкує пароль адміністратора Jenkins"
  value       = "kubectl get secret jenkins-admin -n ${var.namespace} -o jsonpath='{.data.jenkins-admin-password}' | base64 -d"
}

output "port_forward_command" {
  description = "Доступ до UI без LoadBalancer"
  value       = "kubectl port-forward svc/${var.release_name} 8080:8080 -n ${var.namespace}"
}
