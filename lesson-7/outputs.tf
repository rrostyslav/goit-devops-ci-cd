output "aws_region" {
  description = "Регіон AWS, у якому створено інфраструктуру"
  value       = local.aws_region
}

# --- Бекенд для стейту (створюється лише якщо create_state_backend = true) ---

output "s3_bucket_name" {
  description = "Ім'я S3-бакета для стейту Terraform"
  value       = one(module.s3_backend[*].s3_bucket_name)
}

output "s3_bucket_url" {
  description = "URL S3-бакета для стейту Terraform"
  value       = one(module.s3_backend[*].s3_bucket_url)
}

output "dynamodb_table_name" {
  description = "Ім'я DynamoDB-таблиці для блокування стейту"
  value       = one(module.s3_backend[*].dynamodb_table_name)
}

# --- Мережа ---

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

# --- ECR ---

output "ecr_repository_url" {
  description = "URL ECR-репозиторію (значення для image.repository у values.yaml)"
  value       = module.ecr.repository_url
}

output "ecr_login_command" {
  description = "Команда авторизації Docker в ECR"
  value       = "aws ecr get-login-password --region ${local.aws_region} | docker login --username AWS --password-stdin ${split("/", module.ecr.repository_url)[0]}"
}

# --- EKS ---

output "eks_cluster_name" {
  description = "Ім'я EKS-кластера"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "Endpoint Kubernetes API"
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_version" {
  description = "Версія Kubernetes у кластері"
  value       = module.eks.cluster_version
}

output "eks_node_group_name" {
  description = "Ім'я керованої групи воркер-нод"
  value       = module.eks.node_group_name
}

output "eks_oidc_issuer_url" {
  description = "URL OIDC-провайдера кластера (знадобиться для IRSA в наступних темах)"
  value       = module.eks.oidc_issuer_url
}

output "kubectl_config_command" {
  description = "Команда налаштування kubectl на створений кластер"
  value       = module.eks.kubeconfig_command
}
