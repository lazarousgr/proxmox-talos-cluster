variable "proxmox_endpoint" {
    type = string
    description = "The endpoint of the Proxmox API"
}

variable "proxmox_api_token" {
    type = string
    description = "The API token for the Proxmox API"
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
    type = string
    description = "Storage for imported imges (usually local)"
    default = "local"
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