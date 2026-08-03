# =============================================================================
# EBS CSI-драйвер — динамічне створення дисків для PVC
# =============================================================================
# У ДЗ7 сховище було не потрібне: Postgres жив в emptyDir. У ДЗ8-9 з'являється
# Jenkins, а він за замовчуванням просить PersistentVolumeClaim під JENKINS_HOME
# (конфіги, історія збірок, ключі). У EKS немає вбудованого провізіонера томів,
# тож без цього драйвера PVC назавжди залишається в статусі Pending, а под
# Jenkins — у Pending разом з ним.
#
# Драйвер працює як окремий контролер у kube-system і створює EBS-томи через
# API AWS. Права він отримує не з ролі ноди, а через IRSA — власну IAM-роль,
# прив'язану до ServiceAccount `ebs-csi-controller-sa`.

data "aws_iam_policy_document" "ebs_csi_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.cluster.arn]
    }

    # Роль погоджується видати креденшели рівно одному ServiceAccount —
    # тому, який створює сам add-on.
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_host}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  name               = "${var.cluster_name}-ebs-csi-role"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume_role.json

  tags = merge(var.tags, { Name = "${var.cluster_name}-ebs-csi-role" })
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "aws-ebs-csi-driver"

  # Саме ця прив'язка й вмикає IRSA: EKS проставить ServiceAccount анотацію
  # eks.amazonaws.com/role-arn, а вебхук підкине подам змінні AWS_ROLE_ARN
  # і AWS_WEB_IDENTITY_TOKEN_FILE.
  service_account_role_arn = aws_iam_role.ebs_csi.arn

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = merge(var.tags, { Name = "${var.cluster_name}-aws-ebs-csi-driver" })

  depends_on = [
    aws_eks_node_group.main,
    aws_iam_role_policy_attachment.ebs_csi,
  ]
}

# =============================================================================
# StorageClass за замовчуванням
# =============================================================================
# Драйвера самого по собі не достатньо. EKS створює клас `gp2`, але **не
# позначає його дефолтним** і досі описує через in-tree провізіонер
# `kubernetes.io/aws-ebs`. Для PVC без явного `storageClassName` це означає
# «класу немає»: том ніхто не створює, PVC вічно висить у Pending, а под,
# який його чекає, — у Pending разом з ним. Саме так помирає Jenkins.
#
# Тому оголошуємо власний клас на CSI-драйвері й робимо його дефолтним.
resource "kubernetes_storage_class" "default" {
  metadata {
    name = var.default_storage_class_name

    annotations = {
      # Той самий рядок, якого бракує класу gp2 від EKS.
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner = "ebs.csi.aws.com"
  reclaim_policy      = "Delete"

  # Створювати диск лише тоді, коли под уже розподілений на ноду. Інакше в
  # мультизональному кластері EBS-том може виникнути в us-west-2a, под —
  # поїхати на ноду в us-west-2b, і примонтувати його стане неможливо:
  # том не перетинає межу зони доступності.
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  # gp3 дешевший за gp2 приблизно на 20% і дає 3000 IOPS базово,
  # незалежно від розміру диска.
  parameters = {
    type      = "gp3"
    encrypted = "true"
  }

  depends_on = [aws_eks_addon.ebs_csi]
}
