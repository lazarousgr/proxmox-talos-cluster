output "cluster_name" {
  description = "Talos / Kubernetes cluster name"
  value       = var.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint"
  value       = local.cluster_endpoint
}

output "talosconfig" {
  description = "talosctl client configuration"
  value       = data.talos_client_configuration.cluster.talos_config
  sensitive   = true
}

output "kubeconfig" {
  description = "kubectl kubeconfig"
  value       = talos_cluster_kubeconfig.cluster.kubeconfig_raw
  sensitive   = true
}

output "controlplane_ip" {
  value = var.talos_controlplane_ip
}

output "worker_ips" {
  value = var.talos_worker_ips
}
