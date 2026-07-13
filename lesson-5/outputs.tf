output "s3_bucket_name" {
  description = "Ім'я S3-бакета для стейту Terraform"
  value       = module.s3_backend.s3_bucket_name
}

output "s3_bucket_url" {
  description = "URL S3-бакета для стейту Terraform"
  value       = module.s3_backend.s3_bucket_url
}

output "dynamodb_table_name" {
  description = "Ім'я DynamoDB-таблиці для блокування стейту"
  value       = module.s3_backend.dynamodb_table_name
}

output "vpc_id" {
  description = "ID створеної VPC"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "ID публічних підмереж"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "ID приватних підмереж"
  value       = module.vpc.private_subnet_ids
}

output "ecr_repository_url" {
  description = "URL ECR-репозиторію"
  value       = module.ecr.repository_url
}
