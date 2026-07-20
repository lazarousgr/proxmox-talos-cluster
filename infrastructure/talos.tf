locals {
  cluster_endpoint = "https://${var.talos_controlplane_ip}:6443"
  installer_image  = "factory.talos.dev/installer/${var.talos_schematic_id}:v${var.talos_version}"

  worker_nodes = {
    for idx, ip in var.talos_worker_ips : ip => {
      ip       = ip
      hostname = var.talos_node_hostnames.workers[idx]
    }
  }
}

resource "talos_machine_secrets" "cluster" {
  talos_version = "v${var.talos_version}"
}

data "talos_machine_configuration" "controlplane" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = local.cluster_endpoint
  machine_type       = "controlplane"
  machine_secrets    = talos_machine_secrets.cluster.machine_secrets
  talos_version      = "v${var.talos_version}"
  kubernetes_version = var.kubernetes_version
  examples           = false
  docs               = false

  config_patches = [
    yamlencode({
      machine = {
        install = {
          image = local.installer_image
        }
      }
    }),
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "HostnameConfig"
      auto       = "off"
      hostname   = var.talos_node_hostnames.controlplane
    }),
  ]
}

data "talos_machine_configuration" "worker" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = local.cluster_endpoint
  machine_type       = "worker"
  machine_secrets    = talos_machine_secrets.cluster.machine_secrets
  talos_version      = "v${var.talos_version}"
  kubernetes_version = var.kubernetes_version
  examples           = false
  docs               = false

  config_patches = [
    yamlencode({
      machine = {
        install = {
          image = local.installer_image
        }
      }
    }),
  ]
}

data "talos_client_configuration" "cluster" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.cluster.client_configuration
  endpoints            = [var.talos_controlplane_ip]
  nodes                = concat([var.talos_controlplane_ip], var.talos_worker_ips)
}

resource "talos_machine_configuration_apply" "controlplane" {
  client_configuration        = talos_machine_secrets.cluster.client_configuration
  machine_configuration_input = data.talos_machine_configuration.controlplane.machine_configuration
  node                        = var.talos_controlplane_ip
  endpoint                    = var.talos_controlplane_ip

  depends_on = [proxmox_virtual_environment_vm.cp_1]
}

resource "talos_machine_configuration_apply" "worker" {
  for_each = local.worker_nodes

  client_configuration        = talos_machine_secrets.cluster.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker.machine_configuration
  node                        = each.value.ip
  endpoint                    = each.value.ip

  config_patches = [
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "HostnameConfig"
      auto       = "off"
      hostname   = each.value.hostname
    }),
  ]

  depends_on = [
    proxmox_virtual_environment_vm.wrk_1,
    proxmox_virtual_environment_vm.wrk_2,
  ]
}

resource "talos_machine_bootstrap" "cluster" {
  client_configuration = talos_machine_secrets.cluster.client_configuration
  node                 = var.talos_controlplane_ip
  endpoint             = var.talos_controlplane_ip

  depends_on = [
    talos_machine_configuration_apply.controlplane,
    talos_machine_configuration_apply.worker,
  ]
}

resource "talos_cluster_kubeconfig" "cluster" {
  client_configuration = talos_machine_secrets.cluster.client_configuration
  node                 = var.talos_controlplane_ip
  endpoint             = var.talos_controlplane_ip

  depends_on = [talos_machine_bootstrap.cluster]
}
