terraform {
  required_version = ">= 1.5.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.66"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_url
  # formato token: "user@realm!tokenname=<secret-uuid>"
  api_token = "${var.proxmox_token_id}=${var.proxmox_token_secret}"
  insecure  = true  # Proxmox usa certificato TLS self-signed di default
}

locals {
  # Legge la chiave pubblica SSH dal file; generata da setup-bastion.sh in ~/.ssh/id_rsa.pub
  ssh_public_key = trimspace(file(pathexpand(var.ssh_public_key_path)))

  # Estrae il prefisso CIDR dalla subnet  (es. "192.168.1.0/24" → "24")
  cidr_prefix = split("/", var.k8s_subnet)[1]
}
