# =============================================================================
# Prometheus + Grafana
# =============================================================================
# Один чарт замість двох. kube-prometheus-stack — це community-збірка, у якій
# уже зведені докупи: Prometheus Operator, сам Prometheus, Alertmanager,
# node-exporter, kube-state-metrics і Grafana з готовими дашбордами й уже
# налаштованим datasource. Ставити prometheus і grafana окремими релізами теж
# можна, але тоді datasource, ServiceMonitor'и й дашборди доводиться описувати
# руками — а це рівно те, що ця збірка й робить за нас.

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = var.namespace
  }
}

resource "helm_release" "kube_prometheus_stack" {
  name       = var.release_name
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = var.chart_version
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  # Чарт тягне за собою CRD Prometheus Operator (їх близько десятка, і деякі
  # важать сотні кілобайт), тому перша установка помітно довша за звичайну.
  timeout = 900
  wait    = true

  values = [file("${path.module}/values.yaml")]

  # Пароль і тип Service — окремими set, щоб values.yaml лишався статичним
  # файлом без жодного секрету всередині.
  set_sensitive {
    name  = "grafana.adminPassword"
    value = var.grafana_admin_password
  }

  set {
    name  = "grafana.adminUser"
    value = var.grafana_admin_username
  }

  set {
    name  = "grafana.service.type"
    value = var.service_type
  }

  set {
    name  = "prometheus.service.type"
    value = var.service_type
  }

  depends_on = [kubernetes_namespace.monitoring]
}
