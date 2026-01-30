variable "namespace" {
    description = "The namespace to install cert-manager into"
    type        = string
    default     = "cert-manager"
  
}

variable "chart_version" {
  description = "The version of the cert-manager chart to install"
  type        = string
  default     = "1.19.2"
}

variable "values_path" {
    description = "Path to the Helm values file for cert-manager"
    type        = string
    default     = "./values-cert-manager.yaml"
  
}