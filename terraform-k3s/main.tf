locals {
  ssh_public_key = trimspace(file(var.ssh_public_key_path))
  cidr_prefix    = split("/", var.k3s_subnet)[1]

  k3s_nodes = {
    for i in range(var.k3s_count) :
    format("k3s-%d", i + 1) => {
      vm_id      = var.k3s_vm_id_start + i
      ip_address = cidrhost(var.k3s_subnet, var.k3s_ip_start + i)
    }
  }
}

module "k3s_node" {
  source   = "../terraform/modules/proxmox-vm"
  for_each = local.k3s_nodes

  name           = each.key
  description    = "K3S node — gestito da Terraform"
  proxmox_node   = var.proxmox_node
  vm_id          = each.value.vm_id
  template_vm_id = var.template_vm_id

  cores     = var.k3s_cpu_cores
  memory    = var.k3s_memory
  disk_size = var.k3s_disk_size

  storage_pool   = var.storage_pool
  network_bridge = var.network_bridge

  ip_address  = each.value.ip_address
  cidr_prefix = local.cidr_prefix
  gateway     = var.k3s_gateway
  dns_servers = var.dns_servers
  domain      = var.domain

  ssh_public_key = local.ssh_public_key
  tags           = ["k3s"]
}

resource "local_file" "k3s_inventory" {
  filename        = "${path.root}/generated/k3s-inventory.ini"
  file_permission = "0644"

  content = templatefile("${path.root}/templates/k3s-inventory.tftpl", {
    nodes = { for k in keys(local.k3s_nodes) : k => module.k3s_node[k].ip_address }
  })

  depends_on = [module.k3s_node]
}
