# =============================================================================
# Ідентифікація
# =============================================================================

variable "name" {
  description = "Базове ім'я БД та всіх супутніх ресурсів (subnet group, security group, parameter group). Має бути унікальним у межах регіону"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,50}[a-z0-9]$", var.name))
    error_message = "Ім'я має починатися з малої літери, містити лише малі літери, цифри й дефіси, не закінчуватись дефісом і бути коротшим за 52 символи."
  }
}

variable "tags" {
  description = "Теги, що додаються до всіх ресурсів модуля. Тег Name модуль проставляє сам"
  type        = map(string)
  default     = {}
}

# =============================================================================
# Вибір типу БД — головний перемикач модуля
# =============================================================================

variable "use_aurora" {
  description = <<-EOT
    true  — створюється Aurora-кластер (aws_rds_cluster) з writer-інстансом,
            за потреби з reader'ами. Рушій має бути aurora-postgresql або aurora-mysql.
    false — створюється одна звичайна інстанція (aws_db_instance).
            Рушій має бути postgres або mysql.

    Ресурси DB Subnet Group, Security Group і DB Parameter Group створюються
    в обох випадках — змінюється лише те, до чого вони чіпляються.
  EOT
  type        = bool
  default     = false
}

variable "engine" {
  description = "Рушій БД: postgres або mysql для звичайної RDS, aurora-postgresql або aurora-mysql для Aurora. Має бути узгоджений з use_aurora"
  type        = string
  default     = "postgres"

  validation {
    condition     = contains(["postgres", "mysql", "aurora-postgresql", "aurora-mysql"], var.engine)
    error_message = "Допустимі значення: postgres, mysql, aurora-postgresql, aurora-mysql."
  }
}

variable "engine_version" {
  description = <<-EOT
    Версія рушія. Має існувати для обраного engine — перевірити список:
      aws rds describe-db-engine-versions --engine postgres \
        --query 'DBEngineVersions[].EngineVersion' --output text

    Приклади: postgres → "16.14", mysql → "8.0.46",
    aurora-postgresql → "16.14", aurora-mysql → "8.0.mysql_aurora.3.12.0".
  EOT
  type        = string
  default     = "16.14"
}

variable "instance_class" {
  description = <<-EOT
    Клас інстанса. null — модуль підбере дефолт під обрану гілку:
      db.t3.micro   для звичайної RDS (входить у free tier),
      db.t4g.medium для Aurora (менших класів Aurora не пропонує взагалі).

    Спільного дефолту не існує: db.t3.micro для Aurora недоступний, і задати
    його означало б гарантовану помилку на apply.
  EOT
  type        = string
  default     = null
}

variable "multi_az" {
  description = <<-EOT
    Розміщення в кількох зонах доступності. Механізм відрізняється:
      звичайна RDS — синхронний standby в іншій зоні (атрибут multi_az);
      Aurora       — другий інстанс над спільним сховищем, тобто
                     aurora_instance_count стає 2 замість 1.

    Подвоює вартість обчислень.
  EOT
  type        = bool
  default     = false
}

variable "aurora_instance_count" {
  description = "Кількість інстансів у кластері Aurora (перший — writer, решта — reader'и). null — 2 при multi_az = true, інакше 1. Для звичайної RDS не використовується"
  type        = number
  default     = null

  validation {
    condition     = var.aurora_instance_count == null || try(var.aurora_instance_count >= 1 && var.aurora_instance_count <= 15, false)
    error_message = "Кластер Aurora містить від 1 до 15 інстансів."
  }
}

# =============================================================================
# Мережа
# =============================================================================

variable "vpc_id" {
  description = "ID VPC, у якій створюється security group бази"
  type        = string
}

variable "subnet_ids" {
  description = "ID підмереж для DB Subnet Group. Потрібні щонайменше дві в різних зонах доступності — цього вимагає AWS навіть для single-AZ інстанса. Зазвичай приватні підмережі"
  type        = list(string)
}

variable "allowed_cidr_blocks" {
  description = "CIDR-блоки, з яких дозволено підключення до порту БД. Наприклад, CIDR вашої VPC, щоб база була доступна подам EKS"
  type        = list(string)
  default     = []
}

variable "allowed_security_group_ids" {
  description = "ID security group, яким дозволено підключення до порту БД. Точніший спосіб, ніж CIDR: наприклад, лише група нод EKS"
  type        = list(string)
  default     = []
}

variable "publicly_accessible" {
  description = "Чи видавати базі публічний DNS-запис і дозволяти доступ з інтернету. Для БД у приватних підмережах лишайте false"
  type        = bool
  default     = false
}

variable "port" {
  description = "Порт БД. null — 5432 для PostgreSQL, 3306 для MySQL"
  type        = number
  default     = null
}

# =============================================================================
# База та облікові дані
# =============================================================================

variable "database_name" {
  description = "Ім'я бази даних, що створюється всередині інстанса чи кластера"
  type        = string
  default     = "appdb"
}

variable "master_username" {
  description = "Логін майстер-користувача. Значення admin, rdsadmin, guest і подібні зарезервовані AWS і будуть відхилені"
  type        = string
  default     = "dbadmin"

  validation {
    condition     = !contains(["admin", "rdsadmin", "guest", "root", "postgres"], lower(var.master_username))
    error_message = "Логін зарезервований AWS. Оберіть інший, наприклад dbadmin."
  }
}

variable "password" {
  description = <<-EOT
    Пароль майстер-користувача. null (за замовчуванням) — пароль генерує AWS і
    зберігає в Secrets Manager (див. manage_master_user_password), а модуль
    поверне ARN секрету у виводі master_user_secret_arn.

    Задавайте лише через TF_VAR_ або .tfvars — не тримайте у коді.
  EOT
  type        = string
  default     = null
  sensitive   = true

  validation {
    condition     = var.password == null || try(length(var.password) >= 8, false)
    error_message = "AWS вимагає пароль щонайменше з 8 символів."
  }
}

variable "manage_master_user_password" {
  description = "Довірити генерацію й зберігання пароля AWS Secrets Manager. Ігнорується, якщо задано password: разом ці два механізми провайдер не приймає"
  type        = bool
  default     = true
}

# =============================================================================
# Сховище (лише для звичайної RDS)
# =============================================================================
# Aurora цих параметрів не має: її сховище спільне для кластера й розширюється
# автоматично, тому при use_aurora = true значення нижче не використовуються.

variable "allocated_storage" {
  description = "Початковий розмір сховища в ГБ. Мінімум для gp3 — 20"
  type        = number
  default     = 20

  validation {
    condition     = var.allocated_storage >= 20
    error_message = "Мінімальний розмір сховища — 20 ГБ."
  }
}

variable "max_allocated_storage" {
  description = "Межа автоматичного розширення сховища в ГБ. Має бути більшою за allocated_storage; 0 вимикає автоматичне розширення"
  type        = number
  default     = 100
}

variable "storage_type" {
  description = "Тип сховища: gp3 (рекомендовано), gp2 або io1"
  type        = string
  default     = "gp3"

  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2"], var.storage_type)
    error_message = "Допустимі значення: gp2, gp3, io1, io2."
  }
}

variable "storage_encrypted" {
  description = "Шифрування сховища. Вимикати немає причин: воно безкоштовне й після створення БД його вже не увімкнути"
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "ARN власного ключа KMS для шифрування. null — ключ AWS за замовчуванням (aws/rds)"
  type        = string
  default     = null
}

# =============================================================================
# Параметри БД
# =============================================================================

variable "parameters" {
  description = <<-EOT
    Параметри рівня інстанса. Доповнюють і перекривають базовий набір
    (див. use_default_parameters). Ключ — ім'я параметра.

      parameters = {
        max_connections = { value = "200" }
        work_mem        = { value = "8192", apply_method = "immediate" }
      }

    apply_method: "pending-reboot" (за замовчуванням) застосовує зміну при
    наступному перезапуску, "immediate" — одразу. Статичні параметри
    (у PostgreSQL до них належить max_connections) приймають лише
    pending-reboot — AWS відхиляє для них immediate.

    Які параметри існують для вашої родини:
      aws rds describe-engine-default-parameters --db-parameter-group-family postgres16
  EOT
  type = map(object({
    value        = string
    apply_method = optional(string, "pending-reboot")
  }))
  default = {}

  validation {
    condition = alltrue([
      for p in var.parameters : contains(["immediate", "pending-reboot"], p.apply_method)
    ])
    error_message = "apply_method приймає лише immediate або pending-reboot."
  }
}

variable "cluster_parameters" {
  description = <<-EOT
    Параметри рівня кластера Aurora. За замовчуванням порожньо — базові три
    параметри з умови завдання (max_connections, log_statement, work_mem) сюди
    не належать: AWS не знає їх на рівні кластера, вони instance-level і
    задаються через var.parameters.

    Сюди йде те, що справді кластерне, наприклад:
      cluster_parameters = {
        "rds.logical_replication" = { value = "1" }
      }

    Ігнорується при use_aurora = false.
  EOT
  type = map(object({
    value        = string
    apply_method = optional(string, "pending-reboot")
  }))
  default = {}
}

variable "use_default_parameters" {
  description = <<-EOT
    Чи додавати базовий набір параметрів, підібраний під рушій:
      PostgreSQL — max_connections, log_statement, work_mem;
      MySQL      — max_connections, slow_query_log, long_query_time
                   (log_statement і work_mem у MySQL не існують).

    false — у групі буде рівно те, що передано через var.parameters.
  EOT
  type        = bool
  default     = true
}

variable "parameter_group_family" {
  description = <<-EOT
    Родина parameter group. null — обчислюється з engine та engine_version:
      postgres + "16.14"  → postgres16
      mysql + "8.0.46"    → mysql8.0
      aurora-postgresql + "16.14" → aurora-postgresql16

    Задавайте явно, лише якщо автоматичне обчислення не влучило у вашу версію.
  EOT
  type        = string
  default     = null
}

# =============================================================================
# Резервні копії та експлуатація
# =============================================================================

variable "backup_retention_period" {
  description = "Скільки днів зберігати автоматичні резервні копії. 0 вимикає їх (для Aurora мінімум 1)"
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_period >= 0 && var.backup_retention_period <= 35
    error_message = "Допустимий діапазон — від 0 до 35 днів."
  }
}

variable "backup_window" {
  description = "Вікно резервного копіювання в UTC, формат hh24:mi-hh24:mi"
  type        = string
  default     = "03:00-04:00"
}

variable "maintenance_window" {
  description = "Вікно обслуговування в UTC, формат ddd:hh24:mi-ddd:hh24:mi. Не має перетинатися з backup_window"
  type        = string
  default     = "Mon:04:00-Mon:05:00"
}

variable "deletion_protection" {
  description = "Захист від видалення. true не дасть знести базу навіть через terraform destroy, поки прапорець не знято окремим apply"
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Не робити фінальний знімок при видаленні. true зручний для навчального стенду; у проді це один рядок між destroy і безповоротною втратою даних"
  type        = bool
  default     = true
}

variable "final_snapshot_identifier" {
  description = "Ім'я фінального знімка. null — <name>-final-snapshot. Використовується лише при skip_final_snapshot = false"
  type        = string
  default     = null
}

variable "apply_immediately" {
  description = "Застосовувати зміни одразу, а не у вікні обслуговування. Частина змін при цьому спричиняє перезапуск БД"
  type        = bool
  default     = false
}

variable "auto_minor_version_upgrade" {
  description = "Дозволити AWS автоматично оновлювати мінорну версію рушія у вікні обслуговування"
  type        = bool
  default     = true
}

# =============================================================================
# Спостережуваність
# =============================================================================

variable "performance_insights_enabled" {
  description = "Увімкнути Performance Insights. Недоступний на найменших класах інстансів (зокрема db.t3.micro)"
  type        = bool
  default     = false
}

variable "enabled_cloudwatch_logs_exports" {
  description = "Які логи вивантажувати в CloudWatch. null — модуль обере під рушій: [\"postgresql\"] для PostgreSQL, [\"error\", \"slowquery\"] для MySQL. Порожній список вимикає вивантаження"
  type        = list(string)
  default     = null
}
