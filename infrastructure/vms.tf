resource "proxmox_virtual_environment_vm" "cp_1" {
    name = "talos-cp"
    node_name = var.proxmox_node_name
    vm_id = var.talos_cp_vm_id

    description = "Control plane for Talos cluster"
    tags = ["talos", "control-plane", "kubernetes"]

    on_boot = true
    stop_on_destroy = true

    agent {
        enabled = true
    }

    disk {
        datastore_id = "local-lvm"
        file_id      = proxmox_download_file.talos_image.id
        interface    = "scsi0"
        iothread     = true
        discard      = "on"
        size         = 40
    }

    cpu {
        cores = 2
        type = "host"
    }

    memory {
        dedicated = 4096
    }

    network_device {
        bridge      = "vmbr0"
        mac_address = var.talos_cp_mac
    }

    initialization {
        ip_config {
            ipv4 {
                address = "dhcp"
            }
        }
    }

    operating_system {
        type = "l26"
    }

    scsi_hardware = "virtio-scsi-single"
}

resource "proxmox_virtual_environment_vm" "wrk_1" {
    name = "talos-wrk1"
    node_name = var.proxmox_node_name
    vm_id = var.talos_wrk_vm_id[0]

    description = "Worker node 1 for Talos cluster"
    tags = ["talos", "worker-node-1", "kubernetes"]

    on_boot = true
    stop_on_destroy = true

    agent {
        enabled = true
    }

    disk {
        datastore_id = "local-lvm"
        file_id      = proxmox_download_file.talos_image.id
        interface    = "scsi0"
        iothread     = true
        discard      = "on"
        size         = 150
    }

    cpu {
        cores = 4
        type = "host"
    }

    memory {
        dedicated = 16384
    }

    network_device {
        bridge      = "vmbr0"
        mac_address = var.talos_wrk_mac[0]
    }

    initialization {
        ip_config {
            ipv4 {
                address = "dhcp"
            }
        }
    }

    operating_system {
        type = "l26"
    }

    scsi_hardware = "virtio-scsi-single"
}

resource "proxmox_virtual_environment_vm" "wrk_2" {
    name = "talos-wrk2"
    node_name = var.proxmox_node_name_pve2
    vm_id = var.talos_wrk_vm_id[1]

    description = "Worker node 2 for Talos cluster"
    tags = ["talos", "worker-node-2", "kubernetes"]

    on_boot = true
    stop_on_destroy = true

    agent {
        enabled = true
    }

    disk {
        datastore_id = "local-lvm"
        file_id      = proxmox_download_file.talos_image_pve2.id
        interface    = "scsi0"
        iothread     = true
        discard      = "on"
        size         = 150
    }

    cpu {
        cores = 4
        type = "host"
    }

    memory {
        dedicated = 16384
    }

    network_device {
        bridge      = "vmbr0"
        mac_address = var.talos_wrk_mac[1]
    }

    initialization {
        ip_config {
            ipv4 {
                address = "dhcp"
            }
        }
    }

    operating_system {
        type = "l26"
    }

    scsi_hardware = "virtio-scsi-single"
}