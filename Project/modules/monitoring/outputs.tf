output "namespace" {
  description = "Неймспейс, у якому встановлено Prometheus і Grafana"
  value       = kubernetes_namespace.monitoring.metadata[0].name
}

output "release_name" {
  description = "Ім'я Helm-релізу kube-prometheus-stack"
  value       = helm_release.kube_prometheus_stack.name
}

output "chart_version" {
  description = "Версія встановленого чарта"
  value       = helm_release.kube_prometheus_stack.version
}

# --- Grafana ---

output "grafana_service_name" {
  description = "Ім'я Service Grafana. Зафіксоване як `grafana` через fullnameOverride — саме його називає умова завдання"
  value       = "grafana"
}

output "grafana_admin_username" {
  description = "Логін адміністратора Grafana"
  value       = var.grafana_admin_username
}

output "grafana_url_command" {
  description = "Команда, що друкує зовнішній URL Grafana (порожньо, якщо service_type = ClusterIP)"
  value       = "kubectl get svc grafana -n ${var.namespace} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
}

output "grafana_port_forward_command" {
  description = "Доступ до Grafana без LoadBalancer — далі http://localhost:3000"
  value       = "kubectl port-forward svc/grafana 3000:80 -n ${var.namespace}"
}

# --- Prometheus ---

output "prometheus_service_name" {
  description = "Ім'я Service Prometheus (складається з імені релізу)"
  value       = "${var.release_name}-prometheus"
}

output "prometheus_port_forward_command" {
  description = "Доступ до вебінтерфейсу Prometheus — далі http://localhost:9090"
  value       = "kubectl port-forward svc/${var.release_name}-prometheus 9090:9090 -n ${var.namespace}"
}

output "prometheus_targets_command" {
  description = "Перелік таргетів, які Prometheus реально скрапить, без відкривання UI"
  value       = "kubectl exec -n ${var.namespace} sts/prometheus-${var.release_name}-prometheus -c prometheus -- wget -qO- 'http://localhost:9090/api/v1/targets?state=active' | head -c 2000"
}

# --- Alertmanager ---

output "alertmanager_port_forward_command" {
  description = "Доступ до вебінтерфейсу Alertmanager — далі http://localhost:9093"
  value       = "kubectl port-forward svc/${var.release_name}-alertmanager 9093:9093 -n ${var.namespace}"
}
