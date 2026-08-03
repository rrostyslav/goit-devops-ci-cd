# Значення цих змінних — секрети. Передавайте їх через `terraform.tfvars`
# (файл під .gitignore) або змінні середовища `TF_VAR_*`.
# Шаблон — у terraform.tfvars.example.

variable "github_username" {
  description = "Логін GitHub, від імені якого Jenkins клонує репозиторій і пушить оновлений тег"
  type        = string
}

variable "github_token" {
  description = <<-EOT
    GitHub Personal Access Token з правом запису в репозиторій.
    Fine-grained token: Repository access → цей репозиторій,
    Permissions → Repository permissions → Contents: Read and write.
    Використовується і Jenkins (clone + push), і Argo CD (clone).
  EOT
  type        = string
  sensitive   = true
}

variable "jenkins_admin_password" {
  description = "Пароль адміністратора вебінтерфейсу Jenkins (логін — admin)"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.jenkins_admin_password) >= 8
    error_message = "Пароль має бути не коротшим за 8 символів."
  }
}

variable "git_repo_is_public" {
  description = <<-EOT
    true  — Argo CD клонує репозиторій анонімно, секрет доступу не створюється.
    false — Argo CD отримує ті самі github_username і github_token, що й Jenkins.

    Jenkins потребує токен у будь-якому разі: анонімно можна лише читати,
    а він ще й пушить коміт із новим тегом.
  EOT
  type        = bool
  default     = true
}

variable "expose_ui_via_load_balancer" {
  description = <<-EOT
    true  — Jenkins і Argo CD отримують по зовнішньому Service типу LoadBalancer
            (два додаткові ELB, ~$0.045/год разом), URL доступний одразу.
    false — обидва лишаються ClusterIP, доступ через `kubectl port-forward`.
  EOT
  type        = bool
  default     = true
}
