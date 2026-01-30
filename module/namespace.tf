resource "kubernetes_namespace_v1" "cert_manager" {
  metadata {
    name = var.namespace
  }
}
