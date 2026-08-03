data "aws_region" "current" {}

# =============================================================================
# IAM — роль для control plane
# =============================================================================

data "aws_iam_policy_document" "cluster_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${var.cluster_name}-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume_role.json

  tags = merge(var.tags, { Name = "${var.cluster_name}-cluster-role" })
}

resource "aws_iam_role_policy_attachment" "cluster" {
  for_each = toset([
    # Дозволяє EKS керувати ресурсами AWS від імені кластера.
    "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
    # Потрібна для керування ENI (security groups for pods, балансувальники).
    "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController",
  ])

  role       = aws_iam_role.cluster.name
  policy_arn = each.value
}

# =============================================================================
# IAM — роль для воркер-нод
# =============================================================================

data "aws_iam_policy_document" "node_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.cluster_name}-node-role"
  assume_role_policy = data.aws_iam_policy_document.node_assume_role.json

  tags = merge(var.tags, { Name = "${var.cluster_name}-node-role" })
}

# Три обов'язкові політики для воркер-нод EKS:
#   AmazonEKSWorkerNodePolicy            — нода реєструється в кластері;
#   AmazonEKS_CNI_Policy                 — VPC CNI видає подам IP-адреси;
#   AmazonEC2ContainerRegistryReadOnly   — kubelet тягне образи з ECR.
resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
  ])

  role       = aws_iam_role.node.name
  policy_arn = each.value
}

# =============================================================================
# Кластер
# =============================================================================

resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn

  # null → AWS сам підставить поточну дефолтну версію Kubernetes. Так кластер
  # ніколи не створюється на версії, що вже пішла в extended support (дорожче).
  version = var.cluster_version

  vpc_config {
    # Control plane бачить і публічні, і приватні підмережі: публічні потрібні,
    # щоб Service типу LoadBalancer міг створити зовнішній балансувальник.
    subnet_ids              = concat(var.public_subnet_ids, var.private_subnet_ids)
    endpoint_public_access  = var.endpoint_public_access
    endpoint_private_access = var.endpoint_private_access
    public_access_cidrs     = var.public_access_cidrs
  }

  access_config {
    # API + aws-auth ConfigMap. Той, хто створює кластер, автоматично отримує
    # права адміністратора — саме тому `aws eks update-kubeconfig` спрацює
    # одразу після apply, без ручного редагування aws-auth.
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  enabled_cluster_log_types = var.enabled_cluster_log_types

  tags = merge(var.tags, { Name = var.cluster_name })

  depends_on = [aws_iam_role_policy_attachment.cluster]
}

# =============================================================================
# Керована група воркер-нод
# =============================================================================

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-ng"
  node_role_arn   = aws_iam_role.node.arn

  # Ноди — тільки в приватних підмережах, вихід у мережу через NAT Gateway.
  subnet_ids = var.private_subnet_ids

  instance_types = var.node_instance_types
  ami_type       = var.node_ami_type
  capacity_type  = var.node_capacity_type
  disk_size      = var.node_disk_size

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = var.node_labels

  tags = merge(var.tags, { Name = "${var.cluster_name}-ng" })

  # Політики мають бути прикріплені до ролі ДО створення нод, інакше вони
  # не зможуть зареєструватися в кластері.
  depends_on = [aws_iam_role_policy_attachment.node]
}

# =============================================================================
# Add-ons
# =============================================================================

# vpc-cni / kube-proxy / coredns EKS ставить сам, але як «самокеровані»
# компоненти. Оголошення їх як add-on передає керування версіями в AWS
# (OVERWRITE підхоплює вже встановлені), а metrics-server — обов'язкова умова
# роботи HPA: без нього `kubectl get hpa` вічно показує <unknown>/70%.
resource "aws_eks_addon" "main" {
  for_each = toset(var.cluster_addons)

  cluster_name = aws_eks_cluster.main.name
  addon_name   = each.value

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = merge(var.tags, { Name = "${var.cluster_name}-${each.value}" })

  # coredns і metrics-server не запустяться, поки в кластері немає нод.
  depends_on = [aws_eks_node_group.main]
}

# =============================================================================
# Додаткові адміністратори кластера (EKS Access Entries)
# =============================================================================

# Творець кластера вже має права адміністратора. Цей блок потрібен, щоб видати
# доступ ще комусь — наприклад, IAM-ролі Jenkins або Argo CD у наступних темах.
resource "aws_eks_access_entry" "admin" {
  for_each = toset(var.admin_principal_arns)

  cluster_name  = aws_eks_cluster.main.name
  principal_arn = each.value
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "admin" {
  for_each = toset(var.admin_principal_arns)

  cluster_name  = aws_eks_cluster.main.name
  principal_arn = each.value
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.admin]
}
