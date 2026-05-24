terraform {
  required_version = ">= 1.5.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.66"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_url
  api_token = "${var.proxmox_token_id}=${var.proxmox_token_secret}"
  insecure  = true
}

module "vm" {
  source = "../modules/proxmox-vm"

  name           = var.vm_name
  description    = "Single VM — created by create-vm.sh"
  proxmox_node   = var.proxmox_node
  vm_id          = var.vm_id
  template_vm_id = var.template_vm_id

  cores     = var.cores
  memory    = var.memory
  disk_size = var.disk_size

  storage_pool   = var.storage_pool
  network_bridge = var.network_bridge

  ip_address  = var.ip_address
  cidr_prefix = var.cidr_prefix
  gateway     = var.gateway
  dns_servers = var.dns_servers
  domain      = var.domain

  ssh_public_key = trimspace(file(var.ssh_public_key_path))
  tags           = ["single-vm"]
}
