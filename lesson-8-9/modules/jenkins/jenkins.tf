resource "kubernetes_namespace" "jenkins" {
  metadata {
    name = var.namespace
  }
}

# =============================================================================
# Секрети
# =============================================================================
# Чарт Jenkins проєктує обидва секрети в /run/secrets/additional, а плагін
# configuration-as-code підставляє їх у конфіг за іменами ключів. Тому у
# values.yaml нема жодного пароля — там лише посилання виду $${github-token}.

resource "kubernetes_secret" "admin" {
  metadata {
    name      = "jenkins-admin"
    namespace = kubernetes_namespace.jenkins.metadata[0].name
  }

  # Імена ключів фіксовані чартом (controller.admin.userKey / passwordKey).
  data = {
    "jenkins-admin-user"     = var.admin_username
    "jenkins-admin-password" = var.admin_password
  }

  type = "Opaque"
}

resource "kubernetes_secret" "github" {
  metadata {
    name      = "jenkins-github"
    namespace = kubernetes_namespace.jenkins.metadata[0].name
  }

  data = {
    "github-username" = var.github_username
    "github-token"    = var.github_token
  }

  type = "Opaque"
}

# =============================================================================
# IRSA — право агента пушити образи в ECR
# =============================================================================
# Альтернатива — покласти AWS-ключі в креденшели Jenkins, але тоді довгоживучі
# секрети лежать у JENKINS_HOME і в бекапах. IRSA видає подові тимчасові
# креденшели через OIDC: жодного ключа ні в стейті, ні в конфігах.
#
# Kaniko вміє це з коробки — у нього вбудований docker-credential-ecr-login,
# який ходить у AWS STS за токеном (див. config.json у Jenkinsfile).

data "aws_iam_policy_document" "agent_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    # Роль довіряє рівно одному ServiceAccount — тому, під яким Kubernetes-плагін
    # Jenkins запускає поди-агенти. Жоден інший под у кластері її не отримає.
    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_host}:sub"
      values   = ["system:serviceaccount:${var.namespace}:${var.agent_service_account}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "agent" {
  name               = "${var.cluster_name}-jenkins-agent-role"
  assume_role_policy = data.aws_iam_policy_document.agent_assume_role.json

  tags = merge(var.tags, { Name = "${var.cluster_name}-jenkins-agent-role" })
}

data "aws_iam_policy_document" "agent_ecr" {
  # Токен авторизації видається на рівні реєстру, тож звузити Resource тут
  # неможливо — так задумано в AWS.
  statement {
    sid       = "GetAuthorizationToken"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # А от сам push обмежений одним репозиторієм.
  statement {
    sid    = "PushPullImages"
    effect = "Allow"

    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:DescribeRepositories",
      "ecr:DescribeImages",
      "ecr:ListImages",
    ]

    resources = [var.ecr_repository_arn]
  }
}

resource "aws_iam_role_policy" "agent_ecr" {
  name   = "${var.cluster_name}-jenkins-agent-ecr"
  role   = aws_iam_role.agent.id
  policy = data.aws_iam_policy_document.agent_ecr.json
}

# =============================================================================
# Helm-реліз
# =============================================================================

resource "helm_release" "jenkins" {
  name       = var.release_name
  repository = "https://charts.jenkins.io"
  chart      = "jenkins"
  version    = var.chart_version
  namespace  = kubernetes_namespace.jenkins.metadata[0].name

  # Jenkins стартує довго: ініт-контейнер тягне плагіни, потім JCasC розкатує
  # конфіг і створює seed-джобу.
  timeout = 900
  wait    = true

  values = [
    templatefile("${path.module}/values.yaml", {
      service_type              = var.service_type
      persistence_size          = var.persistence_size
      persistence_storage_class = var.persistence_storage_class
      admin_secret_name         = kubernetes_secret.admin.metadata[0].name
      github_secret_name        = kubernetes_secret.github.metadata[0].name
      agent_service_account     = var.agent_service_account
      agent_role_arn            = aws_iam_role.agent.arn

      job_name         = var.job_name
      git_repo_url     = var.git_repo_url
      git_branch       = var.git_branch
      jenkinsfile_path = var.jenkinsfile_path

      ecr_repository_url  = var.ecr_repository_url
      chart_values_path   = var.chart_values_path
      docker_context_path = var.docker_context_path
      aws_region          = var.aws_region
    })
  ]

  depends_on = [
    kubernetes_secret.admin,
    kubernetes_secret.github,
    aws_iam_role_policy.agent_ecr,
  ]
}
