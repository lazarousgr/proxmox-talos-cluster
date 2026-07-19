resource "proxmox_download_file" "talos_image" {
    content_type = "iso"
    datastore_id = var.proxmox_datastore_id
    node_name = var.proxmox_node_name
    url = "https://factory.talos.dev/image/${var.talos_schematic_id}/v${var.talos_version}/nocloud-amd64.raw.xz"
    file_name = "talos-${var.talos_version}-nocloud-amd64.img"
    decompression_algorithm = "zst"
    overwrite = false
    overwrite_unmanaged = false
    verify = false
    upload_timeout = 3600
}

resource "proxmox_download_file" "talos_image_pve2" {
    content_type = "iso"
    datastore_id = var.proxmox_datastore_id
    node_name = var.proxmox_node_name_pve2
    url = "https://factory.talos.dev/image/${var.talos_schematic_id}/v${var.talos_version}/nocloud-amd64.raw.xz"
    file_name = "talos-${var.talos_version}-nocloud-amd64.img"
    decompression_algorithm = "zst"
    overwrite = false
    overwrite_unmanaged = false
    verify = false
    upload_timeout = 3600
}