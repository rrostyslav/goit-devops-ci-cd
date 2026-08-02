terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = local.aws_region
}

locals {
  aws_region   = "us-west-2"
  cluster_name = "lesson-7-eks"

  # S3-бакет і DynamoDB-таблицю для стейту вже створено в ДЗ5, і вони живі.
  # ДЗ7 просто пише в той самий бакет з іншим `key` (див. backend.tf), тому
  # модуль вимкнено. Поставте `true`, якщо бекенду ще не існує — тоді спершу
  # виконайте двоетапний bootstrap, описаний у README.md.
  create_state_backend = false
}

module "s3_backend" {
  source = "./modules/s3-backend"
  count  = local.create_state_backend ? 1 : 0

  # Ім'я має бути глобально унікальним і збігатися з `bucket` у backend.tf.
  bucket_name = "rachynskyi-terraform-state"
  table_name  = "terraform-locks"
}

module "vpc" {
  source = "./modules/vpc"

  vpc_cidr_block     = "10.0.0.0/16"
  public_subnets     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnets    = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
  availability_zones = ["us-west-2a", "us-west-2b", "us-west-2c"]
  vpc_name           = "lesson-7-vpc"

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

  # Кластер піднімається в тій самій мережі, що й решта інфраструктури.
  # Control plane бачить усі підмережі (публічні потрібні для LoadBalancer),
  # а воркер-ноди — тільки в приватних, з виходом у мережу через NAT Gateway.
  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids

  # Не менше t3.small і max_size > 1 — інакше HPA не буде куди шедулити поди
  # і вони назавжди залишаться в статусі Pending.
  node_instance_types = ["t3.small"]
  node_desired_size   = 2
  node_min_size       = 2
  node_max_size       = 3
}
