# =============================================================================
# Гілка use_aurora = true — Aurora-кластер із writer-інстансом
# =============================================================================
# Aurora влаштована інакше, ніж звичайна RDS: сховище відокремлене від
# обчислень і спільне для всього кластера, а інстанси — це лише «голови», що
# до нього підключаються. Звідси три практичні наслідки, помітні в коді нижче:
#
#   1. У кластера немає allocated_storage — сховище росте саме.
#   2. У кластера немає multi_az — відмовостійкість дає другий інстанс в іншій
#      зоні, тому var.multi_az тут керує кількістю інстансів (див. shared.tf).
#   3. Параметрів два рівні: кластерні й інстансні. Обидва нижче.

resource "aws_rds_cluster" "this" {
  count = var.use_aurora ? 1 : 0

  cluster_identifier = var.name

  # --- Рушій ---
  engine         = var.engine
  engine_version = var.engine_version

  # --- База і доступ ---
  database_name   = var.database_name
  master_username = var.master_username
  port            = local.port

  master_password             = var.password
  manage_master_user_password = local.manage_master_password

  # --- Мережа ---
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]

  # --- Сховище ---
  storage_encrypted = var.storage_encrypted
  kms_key_id        = var.kms_key_id

  # --- Параметри ---
  # Кластерна група — для параметрів, спільних для всіх інстансів (наприклад,
  # rds.logical_replication у PostgreSQL). Базових трьох параметрів з умови
  # завдання тут немає: вони instance-level, і чіпляються нижче, на інстансах.
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.this[0].name

  # --- Резервні копії та вікна обслуговування ---
  backup_retention_period      = var.backup_retention_period
  preferred_backup_window      = var.backup_window
  preferred_maintenance_window = var.maintenance_window
  copy_tags_to_snapshot        = true

  # --- Життєвий цикл ---
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : coalesce(var.final_snapshot_identifier, "${var.name}-final-snapshot")
  apply_immediately         = var.apply_immediately

  # --- Спостережуваність ---
  enabled_cloudwatch_logs_exports = local.cloudwatch_logs_exports

  tags = local.tags
}

# Інстанси кластера. Перший (count.index = 0) стає writer'ом, решта —
# read-only репліками: Aurora обирає writer сама, і при відмові підвищує до
# нього одну з реплік. Кількість рахує local.aurora_instance_count.
resource "aws_rds_cluster_instance" "this" {
  count = var.use_aurora ? local.aurora_instance_count : 0

  identifier         = "${var.name}-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.this[0].id

  instance_class = local.instance_class

  # Рушій беремо з кластера, а не з var: якщо змінити версію в одному місці,
  # інстанси не мають розійтись із кластером.
  engine         = aws_rds_cluster.this[0].engine
  engine_version = aws_rds_cluster.this[0].engine_version

  # Та сама група параметрів, що й у звичайної RDS — відрізняється лише родина
  # (aurora-postgresql16 замість postgres16), і її обчислює shared.tf.
  db_parameter_group_name = aws_db_parameter_group.this.name

  db_subnet_group_name       = aws_db_subnet_group.this.name
  publicly_accessible        = var.publicly_accessible
  apply_immediately          = var.apply_immediately
  auto_minor_version_upgrade = var.auto_minor_version_upgrade

  performance_insights_enabled = var.performance_insights_enabled

  tags = merge(var.tags, { Name = "${var.name}-${count.index + 1}" })
}

# =============================================================================
# Cluster Parameter Group — параметри рівня кластера
# =============================================================================
# За замовчуванням порожня, і це свідомо. Спокуса покласти сюди max_connections
# велика, але AWS такого параметра на рівні кластера не знає:
#
#   aws rds describe-engine-default-cluster-parameters \
#     --db-parameter-group-family aurora-postgresql16 \
#     --query "EngineDefaults.Parameters[?ParameterName=='max_connections']"
#
# поверне порожній список. Власна група (замість дефолтної) потрібна, щоб
# кластерні параметри можна було змінити пізніше, не пересоздаючи кластер.

resource "aws_rds_cluster_parameter_group" "this" {
  count = var.use_aurora ? 1 : 0

  name_prefix = "${var.name}-cluster-"
  family      = local.parameter_group_family
  description = "Cluster-level parameters for ${var.name}"

  dynamic "parameter" {
    for_each = var.cluster_parameters

    content {
      name         = parameter.key
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  tags = merge(var.tags, { Name = "${var.name}-cluster-parameters" })

  lifecycle {
    create_before_destroy = true
  }
}
