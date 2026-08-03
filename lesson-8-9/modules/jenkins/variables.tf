variable "namespace" {
  description = "Неймспейс, у якому живе Jenkins"
  type        = string
  default     = "jenkins"
}

variable "release_name" {
  description = "Ім'я Helm-релізу Jenkins"
  type        = string
  default     = "jenkins"
}

variable "chart_version" {
  description = "Версія Helm-чарта jenkins/jenkins"
  type        = string
  default     = "5.9.45"
}

variable "service_type" {
  description = "Тип Service для UI Jenkins: LoadBalancer (зовнішній URL) або ClusterIP (доступ через kubectl port-forward)"
  type        = string
  default     = "LoadBalancer"
}

variable "persistence_size" {
  description = "Розмір PVC під JENKINS_HOME. Потребує EBS CSI-драйвера в кластері"
  type        = string
  default     = "8Gi"
}

# --- Автентифікація в UI ---

variable "admin_username" {
  description = "Логін адміністратора Jenkins"
  type        = string
  default     = "admin"
}

variable "admin_password" {
  description = "Пароль адміністратора Jenkins"
  type        = string
  sensitive   = true
}

# --- Доступ до GitHub ---

variable "github_username" {
  description = "Логін GitHub, від імені якого Jenkins клонує і пушить"
  type        = string
}

variable "github_token" {
  description = "GitHub Personal Access Token з правом Contents: write на репозиторій"
  type        = string
  sensitive   = true
}

variable "git_repo_url" {
  description = "HTTPS-URL репозиторію з Jenkinsfile і Helm-чартом"
  type        = string
}

variable "git_branch" {
  description = "Гілка, з якої береться Jenkinsfile і в яку пайплайн пушить оновлений тег"
  type        = string
}

variable "jenkinsfile_path" {
  description = "Шлях до Jenkinsfile відносно кореня репозиторію"
  type        = string
}

variable "job_name" {
  description = "Ім'я pipeline-джоби, яку створює seed-скрипт JCasC"
  type        = string
  default     = "django-app-ci"
}

# --- Дані, які пайплайн отримує як глобальні змінні середовища ---

variable "ecr_repository_url" {
  description = "URL ECR-репозиторію — Kaniko пушить образ саме туди"
  type        = string
}

variable "chart_values_path" {
  description = "Шлях до values.yaml Helm-чарта відносно кореня репозиторію — у ньому пайплайн оновлює image.tag"
  type        = string
}

variable "docker_context_path" {
  description = "Шлях до контексту збірки (папки з Dockerfile) відносно кореня репозиторію"
  type        = string
}

variable "aws_region" {
  description = "Регіон AWS (потрібен ecr-login helper'у всередині Kaniko)"
  type        = string
}

# --- IRSA ---

variable "cluster_name" {
  description = "Ім'я EKS-кластера (використовується в іменах IAM-ресурсів)"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN OIDC-провайдера кластера з модуля eks"
  type        = string
}

variable "oidc_provider_host" {
  description = "Хост OIDC-провайдера без схеми з модуля eks"
  type        = string
}

variable "ecr_repository_arn" {
  description = "ARN ECR-репозиторію — до нього звужені права агента на push"
  type        = string
}

variable "agent_service_account" {
  description = "Ім'я ServiceAccount, під яким запускаються поди-агенти (до нього прив'язана IAM-роль для push у ECR)"
  type        = string
  default     = "jenkins-agent"
}

variable "tags" {
  description = "Додаткові теги для IAM-ресурсів модуля"
  type        = map(string)
  default     = {}
}
