resource "kubernetes_namespace" "argocd" {
  metadata {
    name = var.namespace
  }
}

# =============================================================================
# Сам Argo CD
# =============================================================================

resource "helm_release" "argocd" {
  name       = var.release_name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.chart_version
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  timeout = 900
  wait    = true

  values = [file("${path.module}/values.yaml")]

  # Тип Service тримаємо окремим set, щоб перемикати LoadBalancer/ClusterIP
  # однією змінною, не чіпаючи values.yaml.
  set {
    name  = "server.service.type"
    value = var.service_type
  }

  depends_on = [kubernetes_namespace.argocd]
}

# =============================================================================
# App-of-apps: Application і Repository як звичайний Helm-чарт
# =============================================================================
# Application можна було б створити ресурсом kubernetes_manifest, але той
# вимагає, щоб CRD argoproj.io вже існували на момент plan — на чистому
# акаунті це неможливо. Локальний чарт цього обмеження не має: Helm
# застосовує маніфести на етапі apply, коли CRD уже стоять.

resource "helm_release" "apps" {
  name      = "${var.release_name}-apps"
  chart     = "${path.module}/charts"
  namespace = kubernetes_namespace.argocd.metadata[0].name

  values = [
    yamlencode({
      argocdNamespace = kubernetes_namespace.argocd.metadata[0].name

      # Для публічного репозиторію креденшели не потрібні — тоді список
      # порожній і Secret не рендериться взагалі.
      repositories = var.git_username == "" ? [] : [
        {
          name     = var.application_name
          url      = var.git_repo_url
          username = var.git_username
          password = var.git_password
        }
      ]

      applications = [
        {
          name                 = var.application_name
          repoURL              = var.git_repo_url
          targetRevision       = var.git_branch
          path                 = var.chart_path
          destinationNamespace = var.destination_namespace
        }
      ]
    })
  ]

  # Application без живого контролера не видаляється: на ньому висить
  # finalizer. Тому реліз чарта завжди зноситься першим, а Argo CD — після
  # нього; інакше `terraform destroy` зависне, а балансувальник застосунку
  # лишиться сиротою й заблокує видалення VPC.
  depends_on = [helm_release.argocd]
}
