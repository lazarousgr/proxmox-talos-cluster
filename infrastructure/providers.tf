provider "proxmox" {
    endpoint = var.proxmox_endpoint
    api_token = var.proxmox_api_token
    insecure = true

    ssh {
        username = "root"
        private_key = file(pathexpand(var.proxmox_ssh_private_key))
    }
}

provider "helm" {
    kubernetes {
        host                   = local.cluster_endpoint
        client_certificate     = base64decode(talos_cluster_kubeconfig.cluster.kubernetes_client_configuration.client_certificate)
        client_key             = base64decode(talos_cluster_kubeconfig.cluster.kubernetes_client_configuration.client_key)
        cluster_ca_certificate = base64decode(talos_cluster_kubeconfig.cluster.kubernetes_client_configuration.ca_certificate)
    }
}