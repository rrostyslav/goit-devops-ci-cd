# =============================================================================
# Спільні ресурси та вся умовна логіка модуля
# =============================================================================
# Цей файл не знає, яку гілку обрано (`rds.tf` чи `aurora.tf`) — він створює те,
# що потрібне обом, і обчислює значення, від яких обидві гілки залежать.
# Уся умовна логіка зібрана в одному `locals` навмисно: коли вона розповзається
# по ресурсах, зміна дефолту перетворюється на полювання по всьому модулю.

locals {
  # --- Родина рушія ----------------------------------------------------------
  # Рушій може бути "postgres", "mysql", "aurora-postgresql" або "aurora-mysql".
  # Ознака родини — підрядок, а не точна назва.
  #
  # regexall, а не strcontains: strcontains з'явився лише в Terraform 1.8, а
  # модуль має лишатись сумісним з 1.5.
  is_mysql = length(regexall("mysql", var.engine)) > 0

  # --- Порт ------------------------------------------------------------------
  port = coalesce(var.port, local.is_mysql ? 3306 : 5432)

  # --- Клас інстансу ---------------------------------------------------------
  # Спільного дефолту для обох гілок не існує: db.t3.micro для Aurora AWS не
  # пропонує взагалі (найменший — db.t3.medium / db.t4g.medium), а тримати
  # db.t4g.medium дефолтом для звичайної RDS означало б платити вчетверо там,
  # де вистачає free-tier інстанса. Перевірити список для свого регіону:
  #   aws rds describe-orderable-db-instance-options \
  #     --engine aurora-postgresql --engine-version 16.14 \
  #     --query 'OrderableDBInstanceOptions[].DBInstanceClass' --output text
  instance_class = coalesce(var.instance_class, var.use_aurora ? "db.t4g.medium" : "db.t3.micro")

  # --- Кількість інстансів Aurora --------------------------------------------
  # У `aws_rds_cluster` немає атрибута multi_az: відмовостійкість Aurora — це
  # не «дзеркальний standby», як у звичайної RDS, а кілька інстансів у різних
  # зонах над спільним сховищем. Тому multi_az тут перетворюється на кількість
  # інстансів: 1 — лише writer, 2 — writer + reader.
  aurora_instance_count = coalesce(var.aurora_instance_count, var.multi_az ? 2 : 1)

  # --- Родина parameter group ------------------------------------------------
  # PostgreSQL рахує родину за мажорною версією ("16.14" → postgres16), MySQL —
  # за двома першими числами ("8.0.46" → mysql8.0). Для aurora-mysql версія має
  # вигляд "8.0.mysql_aurora.3.12.0", і перші два числа так само дають 8.0.
  version_parts = split(".", var.engine_version)

  computed_parameter_group_family = local.is_mysql ? (
    "${var.engine}${join(".", slice(local.version_parts, 0, 2))}"
    ) : (
    "${var.engine}${local.version_parts[0]}"
  )

  parameter_group_family = coalesce(var.parameter_group_family, local.computed_parameter_group_family)

  # --- Базові параметри БД ---------------------------------------------------
  # Найпоширеніша пастка «універсального» модуля: захардкодити три параметри з
  # умови завдання і вважати, що вони є всюди. Насправді `log_statement` і
  # `work_mem` існують ЛИШЕ в PostgreSQL — у родинах mysql8.0 і aurora-mysql8.0
  # їх немає, і apply падає з InvalidParameterValue. Перевірити самому:
  #   aws rds describe-engine-default-parameters --db-parameter-group-family mysql8.0 \
  #     --query "EngineDefaults.Parameters[?ParameterName=='work_mem']"
  #
  # Тому набір за замовчуванням залежить від рушія, а для MySQL підібрано
  # осмислені відповідники: логування повільних запитів замість log_statement.
  #
  # apply_method: `max_connections` у PostgreSQL — статичний параметр (ApplyType
  # static), і AWS відхиляє для нього "immediate". Тому pending-reboot: він
  # приймається завжди, а для динамічних параметрів ми ставимо "immediate" явно.
  default_parameters = local.is_mysql ? {
    max_connections = { value = "100", apply_method = "immediate" }
    slow_query_log  = { value = "1", apply_method = "immediate" }
    long_query_time = { value = "2", apply_method = "immediate" }
    } : {
    max_connections = { value = "100", apply_method = "pending-reboot" }
    log_statement   = { value = "ddl", apply_method = "immediate" }
    work_mem        = { value = "4096", apply_method = "immediate" }
  }

  # var.parameters доповнює і перекриває базовий набір. Щоб зібрати список з
  # нуля — поставте use_default_parameters = false.
  parameters = merge(
    var.use_default_parameters ? local.default_parameters : {},
    var.parameters,
  )

  # --- Логи в CloudWatch -----------------------------------------------------
  # Імена лог-груп теж залежать від рушія: PostgreSQL віддає "postgresql",
  # MySQL — "error" і "slowquery". Явна перевірка на null, а не coalesce: для
  # coalesce порожній список — це валідне значення, і вимкнути вивантаження
  # логів через нього було б неможливо.
  cloudwatch_logs_exports = var.enabled_cloudwatch_logs_exports != null ? var.enabled_cloudwatch_logs_exports : (
    local.is_mysql ? ["error", "slowquery"] : ["postgresql"]
  )

  # --- Пароль майстер-користувача --------------------------------------------
  # Два взаємовиключні механізми: або пароль задає викликач, або його генерує й
  # зберігає AWS Secrets Manager. Передати обидва не можна — провайдер відхиляє
  # password разом із manage_master_user_password, тож другий вимикаємо (null),
  # щойно з'явився перший.
  manage_master_password = var.password == null ? var.manage_master_user_password : null

  # --- Теги ------------------------------------------------------------------
  tags = merge(var.tags, { Name = var.name })
}

# =============================================================================
# DB Subnet Group
# =============================================================================
# Визначає, у яких підмережах RDS розмістить свої мережеві інтерфейси. AWS
# вимагає підмережі щонайменше у двох зонах доступності — навіть для
# single-AZ інстанса, бо інакше йому не буде куди переїхати при відмові зони.

resource "aws_db_subnet_group" "this" {
  name        = "${var.name}-subnet-group"
  description = "Підмережі для ${var.name}"
  subnet_ids  = var.subnet_ids

  tags = merge(var.tags, { Name = "${var.name}-subnet-group" })

  # Перевірки вхідних даних живуть тут, бо цей ресурс створюється завжди,
  # незалежно від значення use_aurora. Помилка спливає на plan — до того, як
  # AWS почне створювати кластер і через 10 хвилин відповість відмовою.
  lifecycle {
    precondition {
      condition     = length(var.subnet_ids) >= 2
      error_message = "AWS вимагає підмережі щонайменше у двох зонах доступності: передано ${length(var.subnet_ids)}."
    }

    precondition {
      condition     = var.use_aurora == (length(regexall("^aurora-", var.engine)) > 0)
      error_message = "Неузгоджені use_aurora і engine: для use_aurora = true рушій має бути aurora-postgresql або aurora-mysql, для false — postgres або mysql. Зараз use_aurora = ${var.use_aurora}, engine = \"${var.engine}\"."
    }

    precondition {
      condition     = var.password != null || var.manage_master_user_password
      error_message = "Пароль не задано: або передайте password, або лишіть manage_master_user_password = true, щоб пароль створив і зберігав AWS Secrets Manager."
    }
  }
}

# =============================================================================
# Security Group
# =============================================================================
# Одна група на базу, з правилами-ресурсами замість вкладених блоків: вкладені
# `ingress`/`egress` вважають, що Terraform знає про всі правила групи, і
# щоразу намагаються прибрати ті, які додав хтось інший.

resource "aws_security_group" "this" {
  name_prefix = "${var.name}-rds-"
  description = "Доступ до бази даних ${var.name}"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-rds-sg" })

  # Групу не можна видалити, поки на неї посилається інстанс, тому спершу
  # створюємо нову, потім переносимо посилання, і лише тоді зникає стара.
  lifecycle {
    create_before_destroy = true
  }
}

# CIDR-блоки — це літерали з конфігурації, тож ключі for_each відомі ще на plan.
resource "aws_vpc_security_group_ingress_rule" "cidr" {
  for_each = toset(var.allowed_cidr_blocks)

  security_group_id = aws_security_group.this.id
  description       = "Доступ до БД з ${each.value}"

  cidr_ipv4   = each.value
  from_port   = local.port
  to_port     = local.port
  ip_protocol = "tcp"

  tags = var.tags
}

# А тут навмисно count, а не for_each: ID групи зазвичай приходить з іншого
# модуля (напр. SG нод EKS) і на plan ще невідомий, а for_each вимагає, щоб
# ключі були відомі. Довжина списку відома завжди, тож count проходить.
resource "aws_vpc_security_group_ingress_rule" "security_group" {
  count = length(var.allowed_security_group_ids)

  security_group_id = aws_security_group.this.id
  description       = "Доступ до БД з дозволеної security group"

  referenced_security_group_id = var.allowed_security_group_ids[count.index]
  from_port                    = local.port
  to_port                      = local.port
  ip_protocol                  = "tcp"

  tags = var.tags
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.this.id
  description       = "Вихідний трафік без обмежень"

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"

  tags = var.tags
}

# =============================================================================
# DB Parameter Group (рівень інстанса)
# =============================================================================
# Спільна для обох гілок, бо всі три базові параметри з умови завдання —
# instance-level. Для Aurora це не очевидно: інтуїція підказує покласти їх у
# cluster parameter group, але `describe-engine-default-cluster-parameters` для
# aurora-postgresql16 не повертає жодного з них. Різниця між гілками — лише в
# родині: postgres16 проти aurora-postgresql16, і її обчислює local вище.

resource "aws_db_parameter_group" "this" {
  name_prefix = "${var.name}-"
  family      = local.parameter_group_family
  description = "Параметри рівня інстанса для ${var.name}"

  dynamic "parameter" {
    for_each = local.parameters

    content {
      name         = parameter.key
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  tags = merge(var.tags, { Name = "${var.name}-parameters" })

  # Зміна параметра зі статичним apply_method пересоздає групу, а від'єднати її
  # від живого інстанса не можна — тому спершу нова, потім стара.
  lifecycle {
    create_before_destroy = true
  }
}
