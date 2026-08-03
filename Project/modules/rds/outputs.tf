# =============================================================================
# Виводи
# =============================================================================
# Набір однаковий для обох гілок: викликач не має знати, Aurora там чи звичайна
# RDS. Значення, яких у гілці не існує (наприклад, reader_endpoint для одиничної
# інстанції), повертаються як null, а не ламають план.
#
# `one(...[*].attr)` — ідіома для ресурсів із count: перетворює список на нуль
# або одне значення й повертає null, коли count = 0.

locals {
  # Хост для підключення. Aurora віддає endpoint кластера — він завжди вказує
  # на поточний writer, і при failover DNS переїжджає сам. Звичайна RDS віддає
  # address (саме хост; атрибут endpoint у неї містить ще й ":порт").
  endpoint = var.use_aurora ? one(aws_rds_cluster.this[*].endpoint) : one(aws_db_instance.this[*].address)

  # Блок master_user_secret існує лише коли пароль генерує AWS, тому try:
  # інакше при заданому password вивід ламав би план.
  master_user_secret_arn = var.use_aurora ? (
    try(aws_rds_cluster.this[0].master_user_secret[0].secret_arn, null)
    ) : (
    try(aws_db_instance.this[0].master_user_secret[0].secret_arn, null)
  )
}

output "is_aurora" {
  description = "Яку гілку створено: true — Aurora-кластер, false — звичайна інстанція"
  value       = var.use_aurora
}

output "identifier" {
  description = "Ідентифікатор створеного кластера або інстанса"
  value       = var.use_aurora ? one(aws_rds_cluster.this[*].cluster_identifier) : one(aws_db_instance.this[*].identifier)
}

output "endpoint" {
  description = "Хост для підключення. Для Aurora — endpoint кластера (завжди вказує на writer), для RDS — адреса інстанса. Без порту: його віддає окремий вивід port"
  value       = local.endpoint
}

output "reader_endpoint" {
  description = "Endpoint для читання, що балансує запити між reader-інстансами. Тільки для Aurora — для звичайної RDS null (її standby недоступний для підключень)"
  value       = var.use_aurora ? one(aws_rds_cluster.this[*].reader_endpoint) : null
}

output "instance_endpoints" {
  description = "Адреси окремих інстансів кластера Aurora. Для звичайної RDS — порожній список"
  value       = aws_rds_cluster_instance.this[*].endpoint
}

output "port" {
  description = "Порт, на якому слухає БД"
  value       = local.port
}

output "database_name" {
  description = "Ім'я створеної бази даних"
  value       = var.database_name
}

output "master_username" {
  description = "Логін майстер-користувача"
  value       = var.master_username
}

output "master_user_secret_arn" {
  description = "ARN секрету в Secrets Manager із паролем, згенерованим AWS. null, якщо пароль передано через змінну password"
  value       = local.master_user_secret_arn
}

output "password_command" {
  description = "Команда, що друкує згенерований AWS пароль. null, якщо пароль задано вручну через змінну password"
  value = local.master_user_secret_arn == null ? null : (
    "aws secretsmanager get-secret-value --secret-id ${local.master_user_secret_arn} --query SecretString --output text"
  )
}

output "connection_command" {
  description = "Готова команда підключення до БД (виконувати з машини всередині VPC — наприклад, з пода в кластері)"
  value = local.is_mysql ? (
    "mysql --host=${local.endpoint} --port=${local.port} --user=${var.master_username} --password ${var.database_name}"
    ) : (
    "psql \"host=${local.endpoint} port=${local.port} user=${var.master_username} dbname=${var.database_name}\""
  )
}

# --- Супутні ресурси ---------------------------------------------------------

output "security_group_id" {
  description = "ID security group бази — передайте його як allowed_security_group_ids іншим ресурсам або використайте для додаткових правил"
  value       = aws_security_group.this.id
}

output "db_subnet_group_name" {
  description = "Ім'я створеної DB Subnet Group"
  value       = aws_db_subnet_group.this.name
}

output "parameter_group_name" {
  description = "Ім'я DB Parameter Group рівня інстанса"
  value       = aws_db_parameter_group.this.name
}

output "cluster_parameter_group_name" {
  description = "Ім'я Cluster Parameter Group. null для звичайної RDS — там кластерного рівня немає"
  value       = one(aws_rds_cluster_parameter_group.this[*].name)
}

# --- Обчислені значення (зручно для перевірки умовної логіки) -----------------

output "parameter_group_family" {
  description = "Родина parameter group, обчислена з engine та engine_version"
  value       = local.parameter_group_family
}

output "instance_class" {
  description = "Клас інстанса, що фактично застосовано (з урахуванням дефолту під обрану гілку)"
  value       = local.instance_class
}

output "applied_parameters" {
  description = "Параметри, що фактично потрапили в DB Parameter Group. Набір залежить від рушія: у MySQL немає log_statement і work_mem"
  value       = local.parameters
}
