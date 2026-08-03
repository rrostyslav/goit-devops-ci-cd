variable "namespace" {
  description = "Неймспейс, у якому живуть Prometheus і Grafana"
  type        = string
  default     = "monitoring"
}

variable "release_name" {
  description = "Ім'я Helm-релізу kube-prometheus-stack. Від нього залежать імена частини сервісів (окрім grafana — його зафіксовано у values.yaml)"
  type        = string
  default     = "kube-prometheus-stack"
}

variable "chart_version" {
  description = "Версія Helm-чарта prometheus-community/kube-prometheus-stack"
  type        = string
  default     = "88.1.3"
}

variable "service_type" {
  description = "Тип Service для UI Grafana і Prometheus: LoadBalancer (зовнішній URL) або ClusterIP (доступ через kubectl port-forward)"
  type        = string
  default     = "ClusterIP"
}

variable "grafana_admin_username" {
  description = "Логін адміністратора Grafana"
  type        = string
  default     = "admin"
}

variable "grafana_admin_password" {
  description = "Пароль адміністратора Grafana"
  type        = string
  sensitive   = true
}
