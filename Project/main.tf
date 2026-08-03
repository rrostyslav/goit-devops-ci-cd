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
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = local.aws_region
}

locals {
  aws_region   = "us-west-2"
  project      = "final-project"
  cluster_name = "${local.project}-eks"

  # Одне джерело правди для CIDR: його отримує і модуль vpc, і модуль rds
  # (як список дозволених адрес). Літерал, а не module.vpc.vpc_cidr_block,
  # навмисно — значення з атрибута ресурсу на plan може бути ще невідомим, а
  # for_each у правилах security group вимагає відомих ключів.
  vpc_cidr = "10.0.0.0/16"

  # S3-бакет і DynamoDB-таблиця для стейту існують з ДЗ5, тому модуль вимкнено:
  # фінальний проєкт пише в той самий бакет з іншим `key` (див. backend.tf).
  #
  # Поставте `true`, якщо розгортаєте все з нуля на порожньому акаунті — тоді
  # спершу виконайте двоетапний bootstrap, описаний у README.md. Інакше перший
  # же `terraform init` впаде: backend.tf вказує на бакет, який створює цей
  # самий код.
  create_state_backend = false

  # --- Контракт між Jenkins, Git і Argo CD -----------------------------------
  # Одне джерело правди для всіх трьох. Помилка в будь-якому з цих рядків
  # ламає ланцюжок мовчки: пайплайн відпрацює зелено, а Argo CD дивитиметься
  # не туди й нічого не задеплоїть.
  project_dir = "Project"

  # HTTPS, а не SSH: Jenkins клонує репозиторій зсередини кластера, де немає
  # ні вашого ~/.ssh, ні ssh-агента. Локально ви й далі працюєте по SSH.
  git_repo_url = "https://github.com/rrostyslav/goit-devops-ci-cd.git"

  # Гілка, у яку пайплайн пушить оновлений тег і за якою стежить Argo CD.
  git_branch = "final-project"

  jenkinsfile_path    = "${local.project_dir}/Django/Jenkinsfile"
  chart_path          = "${local.project_dir}/charts/django-app"
  chart_values_path   = "${local.project_dir}/charts/django-app/values.yaml"
  docker_context_path = "${local.project_dir}/Django"

  # Неймспейс, у який Argo CD розгортає застосунок. Створює його Terraform, а
  # не Argo CD: у цей же неймспейс треба покласти Secret з паролем до RDS ще
  # до першої синхронізації.
  app_namespace = "django-app"

  common_tags = {
    Project   = "goit-ci-cd"
    Stage     = "final-project"
    ManagedBy = "terraform"
  }
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
# Бекенд для стейту
# =============================================================================

module "s3_backend" {
  source = "./modules/s3-backend"
  count  = local.create_state_backend ? 1 : 0

  # Ім'я має бути глобально унікальним і збігатися з `bucket` у backend.tf.
  bucket_name = "rachynskyi-terraform-state"
  table_name  = "terraform-locks"
}

# =============================================================================
# Мережа, реєстр образів, кластер
# =============================================================================

module "vpc" {
  source = "./modules/vpc"

  vpc_cidr_block     = local.vpc_cidr
  public_subnets     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnets    = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
  availability_zones = ["us-west-2a", "us-west-2b", "us-west-2c"]
  vpc_name           = "${local.project}-vpc"

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

  # Три ноди, а не дві, як у ДЗ8-9. У кластері фінального проєкту одночасно
  # живуть Jenkins (~1 ГБ), Argo CD (~1 ГБ), Prometheus з Grafana (~1 ГБ),
  # сам застосунок і транзитні поди-агенти Jenkins. На двох нодах сума
  # requests впритул підходить до ліміту, і черговий под мовчки лишається
  # в Pending — найдорожчий спосіб дізнатися про це вже під час демонстрації.
  #
  # Тип обраний не довільно: акаунт на Free-плані AWS дозволяє запускати ЛИШЕ
  # free-tier-eligible типи, і t3.medium серед них немає — EKS від цього мовчки
  # зависає (див. README, розділ «Типові помилки»). Актуальний список:
  #   aws ec2 describe-instance-types --region us-west-2 \
  #     --filters Name=free-tier-eligible,Values=true --query 'InstanceTypes[].InstanceType'
  #
  # m7i-flex.large: 2 vCPU, 8 ГБ, до 29 подів на ноду, x86_64, ~$0.096/год.
  node_instance_types = ["m7i-flex.large"]
  node_desired_size   = 3
  node_min_size       = 2
  node_max_size       = 5

  tags = local.common_tags
}

# =============================================================================
# База даних
# =============================================================================
# Модуль універсальний: за прапорцем use_aurora він піднімає або Aurora-кластер,
# або звичайну RDS-інстанцію, і сам підбирає клас інстанса, порт, родину
# parameter group і набір параметрів під обраний рушій. Повний опис —
# у modules/rds/README.md.
#
# Переключитись на Aurora — два рядки в terraform.tfvars:
#   use_aurora = true
#   db_engine  = "aurora-postgresql"

# Пароль генерується тут, а не береться з Secrets Manager, і причина
# практична: Terraform має покласти той самий пароль у Kubernetes Secret для
# застосунку. Читати згенерований AWS пароль назад означало б додати
# data-джерело, якого на першому plan ще не існує. Значення все одно осідає
# лише в стейті (він у S3 і зашифрований), а в репозиторії пароля немає.
resource "random_password" "db" {
  count = var.db_password == null ? 1 : 0

  length = 32

  # Виключаємо символи, які RDS відхиляє в паролі: /, " та @.
  special          = true
  override_special = "!#$%&*()-_=+[]{}:?"
}

locals {
  db_password = coalesce(var.db_password, one(random_password.db[*].result))
}

module "rds" {
  source = "./modules/rds"

  name = "${local.project}-db"

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

  password = local.db_password

  # Навчальний стенд: без захисту від видалення й без фінального знімка,
  # щоб `terraform destroy` відпрацював без ручних кроків.
  deletion_protection = false
  skip_final_snapshot = true

  # Дефолт модуля — 7 днів, і для проду це правильно. Але акаунт на Free-плані
  # AWS відхиляє таке значення:
  #   FreeTierRestrictionError: The specified backup retention period exceeds
  #   the maximum available to free tier customers.
  backup_retention_period = 1

  tags = local.common_tags
}

# =============================================================================
# Застосунок: неймспейс і доступ до бази
# =============================================================================
# Неймспейс створює Terraform, хоча Argo CD і вміє це сам (CreateNamespace=true).
# Причина в порядку: Secret з паролем до RDS має існувати ДО першої
# синхронізації, інакше поди застосунку стартують без пароля й падають.
#
# Argo CD цей Secret не чіпає: prune прибирає лише те, що позначене його
# tracking-мітками, а тут їх немає.

resource "kubernetes_namespace" "app" {
  metadata {
    name = local.app_namespace
  }

  depends_on = [module.eks]
}

resource "kubernetes_secret" "app_database" {
  metadata {
    name      = "django-app-db"
    namespace = kubernetes_namespace.app.metadata[0].name
  }

  # Ключ названий так само, як у Secret самого чарта. У Kubernetes при збігу
  # імен виграє останнє джерело в envFrom, а цей Secret додається останнім
  # (values.extraEnvFrom) — тому пароль звідси перекриває значення з чарта.
  data = {
    POSTGRES_PASSWORD = local.db_password
  }

  type = "Opaque"
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

  tags = local.common_tags

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

  application_name = "django-app"

  # Посилання на ресурс, а не на local: так Terraform знає, що неймспейс має
  # з'явитись раніше за Application — і зникнути пізніше за нього.
  destination_namespace = kubernetes_namespace.app.metadata[0].name

  # Координати бази існують лише після apply, тож у Git їх немає й бути не
  # може. Argo CD накладає їх поверх values.yaml під час рендерингу — файл
  # у репозиторії лишається джерелом правди для всього іншого, зокрема для
  # image.tag, який після кожної збірки переписує Jenkins.
  application_values = {
    postgres = {
      # Вбудований PostgreSQL більше не потрібен: у застосунку тепер справжня
      # керована база.
      enabled = false
    }

    config = {
      POSTGRES_HOST = module.rds.endpoint
      POSTGRES_PORT = tostring(module.rds.port)
      POSTGRES_DB   = module.rds.database_name
      POSTGRES_USER = module.rds.master_username
    }

    # Пароль приїжджає посиланням на Secret, а не значенням: у самому
    # Application (звичайному об'єкті кластера) його немає.
    extraEnvFrom = [
      {
        secretRef = {
          name = kubernetes_secret.app_database.metadata[0].name
        }
      }
    ]
  }

  service_type = var.expose_ui_via_load_balancer ? "LoadBalancer" : "ClusterIP"

  depends_on = [module.eks]
}

# =============================================================================
# Моніторинг
# =============================================================================
# kube-prometheus-stack: Prometheus, Alertmanager, node-exporter,
# kube-state-metrics і Grafana з готовими дашбордами й уже підключеним
# datasource — один Helm-реліз замість чотирьох окремих.

module "monitoring" {
  source = "./modules/monitoring"

  grafana_admin_password = var.grafana_admin_password

  # Grafana і Prometheus лишаються без зовнішніх балансувальників навіть тоді,
  # коли їх мають Jenkins і Argo CD: моніторинг віддає внутрішні метрики
  # кластера, і публічний IP йому ні до чого. Умова завдання й перевіряє його
  # через port-forward.
  service_type = "ClusterIP"

  depends_on = [module.eks]
}
