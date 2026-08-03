# =============================================================================
# Гілка use_aurora = false — одна звичайна RDS-інстанція
# =============================================================================
# Класична RDS: один інстанс з власним EBS-сховищем. Відмовостійкість тут —
# синхронна репліка-standby в іншій зоні (multi_az = true), яку не видно ззовні
# й до якої не можна підключитись: вона існує лише для автоматичного failover.
#
# Файл активний тільки коли use_aurora = false. Інакше count = 0, і жодного
# ресурсу звідси в плані немає — так само, як aurora.tf при use_aurora = false.

resource "aws_db_instance" "this" {
  count = var.use_aurora ? 0 : 1

  identifier = var.name

  # --- Рушій ---
  engine         = var.engine
  engine_version = var.engine_version
  instance_class = local.instance_class

  # --- База і доступ ---
  db_name  = var.database_name
  username = var.master_username
  port     = local.port

  password                    = var.password
  manage_master_user_password = local.manage_master_password

  # --- Сховище ---
  # Aurora цих полів не має взагалі: там сховище спільне для кластера й росте
  # саме. Для звичайної RDS розмір задаємо явно, а max_allocated_storage
  # вмикає автоматичне розширення до вказаної межі.
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = var.storage_type
  storage_encrypted     = var.storage_encrypted
  kms_key_id            = var.kms_key_id

  # --- Мережа ---
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]
  publicly_accessible    = var.publicly_accessible
  multi_az               = var.multi_az

  # --- Параметри ---
  parameter_group_name = aws_db_parameter_group.this.name

  # --- Резервні копії та вікна обслуговування ---
  backup_retention_period = var.backup_retention_period
  backup_window           = var.backup_window
  maintenance_window      = var.maintenance_window
  copy_tags_to_snapshot   = true

  # --- Життєвий цикл ---
  # skip_final_snapshot = true зручний для навчального стенду, але в проді це
  # рівно один рядок між `terraform destroy` і безповоротною втратою даних.
  deletion_protection        = var.deletion_protection
  skip_final_snapshot        = var.skip_final_snapshot
  final_snapshot_identifier  = var.skip_final_snapshot ? null : coalesce(var.final_snapshot_identifier, "${var.name}-final-snapshot")
  apply_immediately          = var.apply_immediately
  auto_minor_version_upgrade = var.auto_minor_version_upgrade

  # --- Спостережуваність ---
  performance_insights_enabled    = var.performance_insights_enabled
  enabled_cloudwatch_logs_exports = local.cloudwatch_logs_exports

  tags = local.tags
}
