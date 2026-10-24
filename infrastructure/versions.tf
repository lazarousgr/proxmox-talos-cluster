terraform {
    required_version = ">= 1.5.0"

    required_providers {
        proxmox = {
            source  = "bpg/proxmox"
            version = "0.109.0"
        }
        talos = {
            source  = "siderolabs/talos"
            version = "0.11.0"
        }
        helm = {
            source  = "hashicorp/helm"
            version = "~> 2.17"
        }
    }
}