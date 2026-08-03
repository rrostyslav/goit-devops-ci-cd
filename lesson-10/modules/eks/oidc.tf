# =============================================================================
# OIDC-провайдер кластера — фундамент IRSA
# =============================================================================
# EKS сам по собі видає подам JWT-токени, але AWS їм не довіряє, поки issuer
# кластера не зареєстровано як OpenID Connect provider в IAM. Саме ця
# реєстрація дозволяє IAM-ролі мати trust policy виду «довіряю ServiceAccount
# X у неймспейсі Y цього кластера» — механізм IRSA.
#
# У ДЗ8-9 від нього залежать двоє:
#   * EBS CSI-драйвер (kube-system/ebs-csi-controller-sa) — щоб створювати
#     диски для PVC Jenkins;
#   * агент Jenkins із Kaniko — щоб пушити образи в ECR без статичних ключів.

data "tls_certificate" "cluster" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "cluster" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer

  # Аудиторія токенів, які видає projected service account token у EKS.
  client_id_list = ["sts.amazonaws.com"]

  thumbprint_list = [data.tls_certificate.cluster.certificates[0].sha1_fingerprint]

  tags = merge(var.tags, { Name = "${var.cluster_name}-oidc" })
}

locals {
  # Умови в trust policy пишуться без схеми: `oidc.eks.<region>.amazonaws.com/id/XXXX:sub`.
  oidc_provider_host = replace(aws_iam_openid_connect_provider.cluster.url, "https://", "")
}
