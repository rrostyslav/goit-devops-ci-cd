output "cluster_name" {
  description = "Ім'я EKS-кластера"
  value       = aws_eks_cluster.main.name
}

output "cluster_arn" {
  description = "ARN EKS-кластера"
  value       = aws_eks_cluster.main.arn
}

output "cluster_endpoint" {
  description = "Endpoint Kubernetes API"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_version" {
  description = "Версія Kubernetes у кластері"
  value       = aws_eks_cluster.main.version
}

output "cluster_certificate_authority_data" {
  description = "CA-сертифікат кластера у base64 (для ручного складання kubeconfig)"
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "ID security group, яку EKS створив для кластера"
  value       = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

output "oidc_issuer_url" {
  description = "URL OIDC-провайдера кластера (для IRSA)"
  value       = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

output "oidc_provider_arn" {
  description = "ARN зареєстрованого в IAM OIDC-провайдера — principal у trust policy ролей IRSA"
  value       = aws_iam_openid_connect_provider.cluster.arn
}

output "oidc_provider_host" {
  description = "Хост OIDC-провайдера без схеми — саме в такому вигляді він пишеться в умовах trust policy"
  value       = local.oidc_provider_host
}

output "ebs_csi_role_arn" {
  description = "ARN IAM-ролі EBS CSI-драйвера"
  value       = aws_iam_role.ebs_csi.arn
}

output "node_group_name" {
  description = "Ім'я керованої групи воркер-нод"
  value       = aws_eks_node_group.main.node_group_name
}

output "node_role_arn" {
  description = "ARN IAM-ролі воркер-нод"
  value       = aws_iam_role.node.arn
}

output "kubeconfig_command" {
  description = "Команда налаштування kubectl на цей кластер"
  value       = "aws eks update-kubeconfig --region ${data.aws_region.current.name} --name ${aws_eks_cluster.main.name}"
}

output "default_storage_class_name" {
  description = "Ім'я дефолтного StorageClass — для PVC, які хочуть вказати клас явно"
  value       = kubernetes_storage_class.default.metadata[0].name
}
