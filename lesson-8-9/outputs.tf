output "aws_region" {
  description = "Регіон AWS, у якому створено інфраструктуру"
  value       = local.aws_region
}

# --- Бекенд для стейту (створюється лише якщо create_state_backend = true) ---

output "s3_bucket_name" {
  description = "Ім'я S3-бакета для стейту Terraform"
  value       = one(module.s3_backend[*].s3_bucket_name)
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

output "ecr_list_images_command" {
  description = "Команда, що показує теги образів у ECR — так видно результат роботи пайплайна"
  value       = "aws ecr describe-images --repository-name ${module.ecr.repository_name} --region ${local.aws_region} --query 'sort_by(imageDetails,&imagePushedAt)[*].[imageTags[0],imagePushedAt]' --output table"
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

output "eks_oidc_provider_arn" {
  description = "ARN OIDC-провайдера кластера — основа IRSA для EBS CSI і агента Jenkins"
  value       = module.eks.oidc_provider_arn
}

output "kubectl_config_command" {
  description = "Команда налаштування kubectl на створений кластер"
  value       = module.eks.kubeconfig_command
}

# --- Jenkins ---

output "jenkins_namespace" {
  description = "Неймспейс Jenkins"
  value       = module.jenkins.namespace
}

output "jenkins_job_name" {
  description = "Ім'я pipeline-джоби, створеної через JCasC"
  value       = module.jenkins.job_name
}

output "jenkins_admin_username" {
  description = "Логін адміністратора Jenkins"
  value       = module.jenkins.admin_username
}

output "jenkins_url_command" {
  description = "Команда, що друкує зовнішній URL Jenkins (порт 8080)"
  value       = module.jenkins.url_command
}

output "jenkins_password_command" {
  description = "Команда, що друкує пароль адміністратора Jenkins"
  value       = module.jenkins.password_command
}

output "jenkins_port_forward_command" {
  description = "Доступ до Jenkins без LoadBalancer — далі http://localhost:8080"
  value       = module.jenkins.port_forward_command
}

output "jenkins_agent_role_arn" {
  description = "ARN IAM-ролі агента Jenkins (IRSA) — з нею Kaniko пушить у ECR"
  value       = module.jenkins.agent_role_arn
}

# --- Argo CD ---

output "argocd_namespace" {
  description = "Неймспейс Argo CD"
  value       = module.argo_cd.namespace
}

output "argocd_application_name" {
  description = "Ім'я Argo CD Application"
  value       = module.argo_cd.application_name
}

output "argocd_url_command" {
  description = "Команда, що друкує зовнішній URL Argo CD (порт 80)"
  value       = module.argo_cd.url_command
}

output "argocd_password_command" {
  description = "Команда, що друкує початковий пароль admin для Argo CD"
  value       = module.argo_cd.password_command
}

output "argocd_port_forward_command" {
  description = "Доступ до Argo CD без LoadBalancer — далі http://localhost:8081"
  value       = module.argo_cd.port_forward_command
}

# --- Застосунок ---

output "app_namespace" {
  description = "Неймспейс, у який Argo CD розгортає Django-застосунок"
  value       = module.argo_cd.destination_namespace
}

output "app_url_command" {
  description = "Команда, що друкує зовнішній URL Django-застосунку"
  value       = "kubectl get svc ${module.argo_cd.application_name} -n ${module.argo_cd.destination_namespace} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
}

# --- Контракт CI/CD ---

output "cicd_contract" {
  description = "Значення, які мають збігатися в Jenkins, Git і Argo CD"
  value = {
    git_repo_url        = local.git_repo_url
    git_branch          = local.git_branch
    jenkinsfile_path    = local.jenkinsfile_path
    docker_context_path = local.docker_context_path
    chart_path          = local.chart_path
    chart_values_path   = local.chart_values_path
  }
}
