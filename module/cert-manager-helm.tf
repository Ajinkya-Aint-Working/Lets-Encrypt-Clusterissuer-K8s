resource "helm_release" "cert_manager" {
  name      = "cert-manager"
  namespace = kubernetes_namespace_v1.cert_manager.metadata[0].name

  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"

  # 🔒 FIXED chart version (matches existing cluster)
  version = var.chart_version

  values = [
    file(var.values_path)
  ]

  wait    = true
  timeout = 600

  force_update  = true
  recreate_pods = true

  depends_on = [
    kubernetes_namespace_v1.cert_manager
  ]
}
