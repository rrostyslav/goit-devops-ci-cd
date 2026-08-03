terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.35"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
  }
}

provider "aws" {
  region = local.aws_region
}

locals {
  aws_region   = "us-west-2"
  cluster_name = "lesson-10-eks"

  # Одне джерело правди для CIDR: його отримує і модуль vpc, і модуль rds
  # (як список дозволених адрес). Літерал, а не module.vpc.vpc_cidr_block,
  # навмисно — значення з атрибута ресурсу на plan може бути ще невідомим, а
  # for_each у правилах security group вимагає відомих ключів.
  vpc_cidr = "10.0.0.0/16"

  # Прапорець теми 10. false — база не створюється взагалі (жодного ресурсу
  # RDS у плані), решта інфраструктури піднімається як у ДЗ8-9.
  create_database = true

  # S3-бакет і DynamoDB-таблицю для стейту створено ще в ДЗ5, і вони живі.
  # ДЗ10 пише в той самий бакет з іншим `key` (див. backend.tf), тому модуль
  # вимкнено. Поставте `true`, якщо бекенду ще не існує — тоді спершу
  # виконайте двоетапний bootstrap, описаний у README.md.
  create_state_backend = false

  # --- Контракт між Jenkins, Git і Argo CD -----------------------------------
  # Одне джерело правди для всіх трьох. Помилка в будь-якому з цих рядків
  # ламає ланцюжок мовчки: пайплайн відпрацює зелено, а Argo CD дивитиметься
  # не туди й нічого не задеплоїть.
  lesson_dir = "lesson-10"

  # HTTPS, а не SSH: Jenkins клонує репозиторій зсередини кластера, де немає
  # ні вашого ~/.ssh, ні ssh-агента. Локально ви й далі працюєте по SSH.
  git_repo_url = "https://github.com/rrostyslav/goit-devops-ci-cd.git"
  git_branch   = "lesson-10"

  jenkinsfile_path    = "${local.lesson_dir}/Jenkinsfile"
  chart_path          = "${local.lesson_dir}/charts/django-app"
  chart_values_path   = "${local.lesson_dir}/charts/django-app/values.yaml"
  docker_context_path = "${local.lesson_dir}/django-app"
}

# =============================================================================
# Провайдери Kubernetes і Helm
# =============================================================================
# Автентифікація через `aws eks get-token`: токен живе 15 хвилин і не
# зберігається в стейті — на відміну від атрибута `token` у конфігу провайдера.
#
# Ім'я кластера беремо з local, а не з module.eks.cluster_name: воно відоме
# ще до створення кластера, тож у конфігурації провайдера лишається на одне
# невідоме значення менше.

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", local.cluster_name, "--region", local.aws_region]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", local.cluster_name, "--region", local.aws_region]
    }
  }
}

# =============================================================================
# Інфраструктура
# =============================================================================

module "s3_backend" {
  source = "./modules/s3-backend"
  count  = local.create_state_backend ? 1 : 0

  # Ім'я має бути глобально унікальним і збігатися з `bucket` у backend.tf.
  bucket_name = "rachynskyi-terraform-state"
  table_name  = "terraform-locks"
}

module "vpc" {
  source = "./modules/vpc"

  vpc_cidr_block     = local.vpc_cidr
  public_subnets     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnets    = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
  availability_zones = ["us-west-2a", "us-west-2b", "us-west-2c"]
  vpc_name           = "lesson-10-vpc"

  # Теги для EKS: без них Service типу LoadBalancer не знайде підмережі
  # й вічно висітиме зі статусом `<pending>` у колонці EXTERNAL-IP.
  cluster_name = local.cluster_name
}

module "ecr" {
  source = "./modules/ecr"

  ecr_name     = "django-app"
  scan_on_push = true
}

module "eks" {
  source = "./modules/eks"

  cluster_name = local.cluster_name

  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids

  # Більша нода, ніж t3.small із ДЗ7: у кластері тепер живуть ще й Jenkins
  # (~1 ГБ) та компоненти Argo CD (~1 ГБ разом). На 2 ГБ ноди для них просто
  # не лишилось би місця, і поди зависли б у Pending.
  #
  # Але тип обраний не довільно. Акаунт на Free-плані AWS дозволяє запускати
  # ЛИШЕ free-tier-eligible типи, і t3.medium серед них немає — EKS від цього
  # мовчки зависає (див. README, розділ «Типові помилки»). Актуальний список:
  #   aws ec2 describe-instance-types --region us-west-2 \
  #     --filters Name=free-tier-eligible,Values=true --query 'InstanceTypes[].InstanceType'
  #
  # m7i-flex.large: 2 vCPU, 8 ГБ, до 29 подів на ноду, x86_64, ~$0.096/год.
  # Дешевша альтернатива з тим самим лімітом подів — c7i-flex.large (4 ГБ).
  node_instance_types = ["m7i-flex.large"]
  node_desired_size   = 2
  node_min_size       = 2
  node_max_size       = 4
}

# =============================================================================
# База даних — тема 10
# =============================================================================
# Той самий виклик обслуговує обидва сценарії: `use_aurora = false` дає одну
# звичайну інстанцію, `true` — Aurora-кластер. Решта аргументів не змінюється,
# бо клас інстанса, порт, родину parameter group і набір параметрів модуль
# підбирає сам під обраний рушій.
#
# Переключитись на Aurora — два рядки в terraform.tfvars:
#   use_aurora     = true
#   db_engine      = "aurora-postgresql"

module "rds" {
  source = "./modules/rds"
  count  = local.create_database ? 1 : 0

  name = "lesson-10-db"

  use_aurora     = var.use_aurora
  engine         = var.db_engine
  engine_version = var.db_engine_version

  # null — модуль обере дефолт під гілку: db.t3.micro для RDS,
  # db.t4g.medium для Aurora (менших класів Aurora не пропонує).
  instance_class = var.db_instance_class
  multi_az       = var.db_multi_az

  # Приватні підмережі: саме в них живуть ноди EKS, тож база доступна подам,
  # але не з інтернету.
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  allowed_cidr_blocks = [local.vpc_cidr]
  publicly_accessible = false

  database_name   = "django_db"
  master_username = "django_user"

  # Пароль не заданий — його згенерує AWS і покладе в Secrets Manager.
  # Прочитати: `terraform output -raw rds_password_command` і виконати.
  password = var.db_password

  # Навчальний стенд: без захисту від видалення й без фінального знімка,
  # щоб `terraform destroy` відпрацював без ручних кроків.
  deletion_protection = false
  skip_final_snapshot = true

  tags = {
    Project = "goit-ci-cd"
    Lesson  = "10"
  }
}

# =============================================================================
# CI/CD
# =============================================================================

module "jenkins" {
  source = "./modules/jenkins"

  cluster_name = module.eks.cluster_name

  admin_password  = var.jenkins_admin_password
  github_username = var.github_username
  github_token    = var.github_token

  git_repo_url     = local.git_repo_url
  git_branch       = local.git_branch
  jenkinsfile_path = local.jenkinsfile_path

  ecr_repository_url  = module.ecr.repository_url
  chart_values_path   = local.chart_values_path
  docker_context_path = local.docker_context_path
  aws_region          = local.aws_region

  # IRSA: агент отримує права на push у ECR через OIDC кластера,
  # без жодного статичного AWS-ключа в Jenkins.
  oidc_provider_arn  = module.eks.oidc_provider_arn
  oidc_provider_host = module.eks.oidc_provider_host
  ecr_repository_arn = module.ecr.repository_arn

  service_type = var.expose_ui_via_load_balancer ? "LoadBalancer" : "ClusterIP"

  # Клас сховища вказуємо явно: EKS створює `gp2`, але не робить його
  # дефолтним, тож PVC без явного класу вічно висить у Pending.
  persistence_storage_class = module.eks.default_storage_class_name

  # Без нод і CSI-драйвера PVC Jenkins нема кому обслужити.
  depends_on = [module.eks]
}

module "argo_cd" {
  source = "./modules/argo_cd"

  git_repo_url = local.git_repo_url
  git_branch   = local.git_branch
  chart_path   = local.chart_path

  # Публічний репозиторій Argo CD читає анонімно, тож токен йому не потрібен —
  # і секрет із ним у кластері не з'являється взагалі. Для приватного репо
  # поставте git_repo_is_public = false, і сюди поїде той самий PAT, що в Jenkins.
  git_username = var.git_repo_is_public ? "" : var.github_username
  git_password = var.git_repo_is_public ? "" : var.github_token

  application_name      = "django-app"
  destination_namespace = "django-app"

  service_type = var.expose_ui_via_load_balancer ? "LoadBalancer" : "ClusterIP"

  depends_on = [module.eks]
}
