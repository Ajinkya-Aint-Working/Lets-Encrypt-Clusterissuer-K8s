output "namespace" {
  value = kubernetes_namespace_v1.cert_manager.metadata[0].name
}

output "helm_release_name" {
  value = helm_release.cert_manager.name
}

output "chart_version" {
  value = helm_release.cert_manager.version
}
