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

variable "grafana_admin_password" {
  description = "Пароль адміністратора Grafana (логін — admin)"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.grafana_admin_password) >= 8
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
    false — обидва лишаються ClusterIP, доступ через `kubectl port-forward`,
            саме як описано в умові завдання.

    На Grafana й Prometheus не впливає: у них завжди ClusterIP.
  EOT
  type        = bool
  default     = false
}

# =============================================================================
# База даних
# =============================================================================
# Ці шість змінних — усе, що потрібно, щоб перемкнути модуль rds між звичайною
# RDS і Aurora. Решту (порт, клас інстанса, родину parameter group, набір
# параметрів) модуль виводить із них сам.

variable "use_aurora" {
  description = <<-EOT
    true  — модуль rds створює Aurora-кластер із writer-інстансом.
            Разом із цим змініть db_engine на aurora-postgresql.
    false — створюється одна звичайна інстанція aws_db_instance.

    Aurora дорожча: найменший доступний клас — db.t4g.medium (~$0.073/год)
    проти db.t3.micro (~$0.018/год) у звичайної RDS.
  EOT
  type        = bool
  default     = false
}

variable "db_engine" {
  description = "Рушій БД: postgres при use_aurora = false, aurora-postgresql при true. Неузгодженість модуль ловить на plan"
  type        = string
  default     = "postgres"

  validation {
    # Модуль rds підтримує ще й MySQL, але Django-застосунок цього проєкту
    # ходить у базу через psycopg2 — тобто до MySQL він не підключиться.
    # Перевірка тут, а не в модулі: сам модуль лишається універсальним.
    condition     = length(regexall("postgres", var.db_engine)) > 0
    error_message = "Django-застосунок цього проєкту працює лише з PostgreSQL: допустимі значення — postgres або aurora-postgresql."
  }
}

variable "db_engine_version" {
  description = "Версія рушія. Для postgres і aurora-postgresql — 16.14"
  type        = string
  default     = "16.14"
}

variable "db_instance_class" {
  description = "Клас інстанса БД. null — модуль обере дефолт під обрану гілку (db.t3.micro для RDS, db.t4g.medium для Aurora)"
  type        = string
  default     = null
}

variable "db_multi_az" {
  description = "Розміщення в кількох зонах доступності. Для звичайної RDS — синхронний standby, для Aurora — другий інстанс. Подвоює вартість"
  type        = bool
  default     = false
}

variable "db_password" {
  description = <<-EOT
    Пароль майстер-користувача БД. null (за замовчуванням) — Terraform згенерує
    його сам через random_password і покладе той самий рядок у Kubernetes Secret,
    з якого його читає застосунок. Задавайте явно лише тоді, коли пароль має
    збігтися з уже наявним.
  EOT
  type        = string
  default     = null
  sensitive   = true
}
