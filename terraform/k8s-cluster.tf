# ── Topologia del cluster ──────────────────────────────────────────────────────
#
# Nomi, VM ID e IP vengono calcolati dalle variabili:
#
#   master_name_prefix="cp" master_vm_id_start=101 master_ip_start=10 count=3
#     → cp-1  VMID=101  IP=192.168.1.10
#     → cp-2  VMID=102  IP=192.168.1.11
#     → cp-3  VMID=103  IP=192.168.1.12
#
#   worker_name_prefix="node" worker_vm_id_start=201 worker_ip_start=20 count=3
#     → node-1  VMID=201  IP=192.168.1.20
#     → node-2  VMID=202  IP=192.168.1.21
#     → node-3  VMID=203  IP=192.168.1.22

locals {
  control_plane_nodes = {
    for i in range(var.control_plane_count) :
    format("%s-%d", var.master_name_prefix, i + 1) => {
      vm_id      = var.master_vm_id_start + i
      ip_address = cidrhost(var.k8s_subnet, var.master_ip_start + i)
    }
  }

  worker_nodes = {
    for i in range(var.worker_count) :
    format("%s-%d", var.worker_name_prefix, i + 1) => {
      vm_id      = var.worker_vm_id_start + i
      ip_address = cidrhost(var.k8s_subnet, var.worker_ip_start + i)
    }
  }
}

# ── Nodi control plane ─────────────────────────────────────────────────────────
module "k8s_master" {
  source   = "./modules/proxmox-vm"
  for_each = local.control_plane_nodes

  name           = each.key
  description    = "Kubernetes control plane — gestito da Terraform"
  proxmox_node   = var.proxmox_node
  vm_id          = each.value.vm_id
  template_vm_id = var.template_vm_id

  cores     = var.master_cpu_cores
  memory    = var.master_memory
  disk_size = var.master_disk_size

  storage_pool   = var.storage_pool
  network_bridge = var.network_bridge

  ip_address  = each.value.ip_address
  cidr_prefix = local.cidr_prefix
  gateway     = var.k8s_gateway
  dns_servers = var.dns_servers
  domain      = var.domain

  ssh_public_key = local.ssh_public_key
  tags           = ["kubernetes", "control-plane"]
}

# ── Nodi worker ────────────────────────────────────────────────────────────────
module "k8s_worker" {
  source   = "./modules/proxmox-vm"
  for_each = local.worker_nodes

  name           = each.key
  description    = "Kubernetes worker node — gestito da Terraform"
  proxmox_node   = var.proxmox_node
  vm_id          = each.value.vm_id
  template_vm_id = var.template_vm_id

  cores     = var.worker_cpu_cores
  memory    = var.worker_memory
  disk_size = var.worker_disk_size

  storage_pool   = var.storage_pool
  network_bridge = var.network_bridge

  ip_address  = each.value.ip_address
  cidr_prefix = local.cidr_prefix
  gateway     = var.k8s_gateway
  dns_servers = var.dns_servers
  domain      = var.domain

  ssh_public_key = local.ssh_public_key
  tags           = ["kubernetes", "worker"]
}

# ── Inventory Kubespray (generato automaticamente) ─────────────────────────────
#
# Dopo ogni `terraform apply`, aggiorna terraform/generated/kubespray-inventory.ini
# con gli IP reali delle VM. Copiarlo in kubespray/inventory/homelab/hosts.ini
# prima di eseguire Kubespray.
resource "local_file" "kubespray_inventory" {
  filename        = "${path.root}/generated/kubespray-inventory.ini"
  file_permission = "0644"

  content = templatefile("${path.root}/templates/kubespray-inventory.tftpl", {
    control_plane = { for k in keys(local.control_plane_nodes) : k => module.k8s_master[k].ip_address }
    workers       = { for k in keys(local.worker_nodes) : k => module.k8s_worker[k].ip_address }
  })

  depends_on = [module.k8s_master, module.k8s_worker]
}
