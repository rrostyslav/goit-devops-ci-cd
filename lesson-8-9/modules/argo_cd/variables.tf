variable "namespace" {
  description = "Неймспейс, у якому живе Argo CD"
  type        = string
  default     = "argocd"
}

variable "release_name" {
  description = "Ім'я Helm-релізу Argo CD"
  type        = string
  default     = "argocd"
}

variable "chart_version" {
  description = "Версія Helm-чарта argo/argo-cd"
  type        = string
  default     = "10.2.2"
}

variable "service_type" {
  description = "Тип Service для UI Argo CD: LoadBalancer або ClusterIP (доступ через kubectl port-forward)"
  type        = string
  default     = "LoadBalancer"
}

# --- Репозиторій, за яким стежить Argo CD ---

variable "git_repo_url" {
  description = "HTTPS-URL Git-репозиторію з Helm-чартом"
  type        = string
}

variable "git_branch" {
  description = "Гілка, за якою стежить Application (targetRevision)"
  type        = string
}

variable "chart_path" {
  description = "Шлях до Helm-чарта всередині репозиторію"
  type        = string
}

variable "git_username" {
  description = "Логін для приватного репозиторію. Порожній рядок — репозиторій публічний, креденшели не створюються"
  type        = string
  default     = ""
}

variable "git_password" {
  description = "PAT для приватного репозиторію"
  type        = string
  default     = ""
  sensitive   = true
}

# --- Application ---

variable "application_name" {
  description = "Ім'я Argo CD Application"
  type        = string
  default     = "django-app"
}

variable "destination_namespace" {
  description = "Неймспейс, у який Argo CD розгортає застосунок"
  type        = string
  default     = "django-app"
}
