variable "proxmox_endpoint" {
    type = string
    description = "The endpoint of the Proxmox API"
}

variable "proxmox_api_token" {
    type        = string
    description = "The API token for the Proxmox API"
    sensitive   = true
}

variable "proxmox_node_name" {
    type = string
    description = "The name of the Proxmox node"
}

variable "proxmox_node_name_pve2" {
    type = string
    description = "The name of the Proxmox node 2"
}

variable "proxmox_datastore_id" {
    type        = string
    description = "Storage for imported images (usually local)"
    default     = "local"
}

variable "talos_version" {
    type = string
    description = "Talos version to install"
}

variable "talos_schematic_id" {
    type = string
    description = "Image factory schematic ID for Talos"
}

variable "proxmox_ssh_private_key" {
    type = string
    description = "The private key for the Proxmox SSH connection"
}

variable "cluster_name" {
    type        = string
    description = "Talos / Kubernetes cluster name"
    default     = "talos-homelab"
}

variable "kubernetes_version" {
    type        = string
    description = "Kubernetes version without v prefix (must match Talos support matrix)"
    default     = "1.36.2"
}

variable "talos_controlplane_ip" {
    type        = string
    description = "Control plane node IP (also used as cluster API endpoint host)"
}

variable "talos_worker_ips" {
    type        = list(string)
    description = "Worker node IPs"
}

variable "talos_node_hostnames" {
    type = object({
        controlplane = string
        workers      = list(string)
    })
    description = "Hostnames applied via Talos HostnameConfig"
    default = {
        controlplane = "talos-cp"
        workers      = ["talos-wrk1", "talos-wrk2"]
    }
}

variable "talos_cp_mac" {
    type        = string
    description = "Control plane NIC MAC (must match DHCP reservation)"
}

variable "talos_wrk_mac" {
    type        = list(string)
    description = "Worker NIC MACs in the same order as talos_worker_ips"

    validation {
        condition     = length(var.talos_wrk_mac) == length(var.talos_worker_ips)
        error_message = "talos_wrk_mac length must match talos_worker_ips."
    }
}

variable "talos_cp_vm_id" {
    type        = number
    description = "Proxmox VM ID for the control plane"
    default     = 800
}

variable "talos_wrk_vm_id" {
    type        = list(number)
    description = "Proxmox VM IDs for workers (same order as talos_worker_ips); IDs are per-node"
    default     = [801, 810]

    validation {
        condition     = length(var.talos_wrk_vm_id) == length(var.talos_worker_ips)
        error_message = "talos_wrk_vm_id length must match talos_worker_ips."
    }
}