packer {
  required_plugins {
    proxmox = {
      version = ">= 1.1.3"
      source  = "github.com/hashicorp/proxmox"
    }
    ansible = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/ansible"
    }
  }
}

# ── Proxmox connection ────────────────────────────────────────────────────────
variable "proxmox_url" {
  type        = string
  description = "Proxmox API URL  (es. https://192.168.1.10:8006/api2/json)"
  default     = env("PROXMOX_URL")
}

variable "proxmox_token_id" {
  type        = string
  description = "Token ID Proxmox API  (es. automation@pve!packer)"
  default     = env("PROXMOX_TOKEN_ID")
}

variable "proxmox_token_secret" {
  type        = string
  sensitive   = true
  description = "Token secret UUID Proxmox API"
  default     = env("PROXMOX_TOKEN_SECRET")
}

variable "proxmox_node" {
  type        = string
  description = "Nome del nodo Proxmox su cui costruire la VM"
  default     = "pve"
}

# ── VM IDs per distribuzione ──────────────────────────────────────────────────
variable "vm_id_rocky_9" {
  type        = number
  description = "VM ID Proxmox per il template Rocky 9"
  default     = 9000
}

variable "vm_id_ubuntu_2204" {
  type        = number
  description = "VM ID Proxmox per il template Ubuntu 22.04"
  default     = 9001
}

variable "vm_id_ubuntu_2404" {
  type        = number
  description = "VM ID Proxmox per il template Ubuntu 24.04"
  default     = 9002
}

variable "vm_id_debian_13" {
  type        = number
  description = "VM ID Proxmox per il template Debian 13"
  default     = 9003
}

variable "network_bridge" {
  type        = string
  description = "Bridge di rete Proxmox"
  default     = "vmbr0"
}

variable "disk_size" {
  type        = string
  description = "Dimensione disco del template"
  default     = "32G"
}

variable "cores" {
  type        = number
  description = "Core CPU della VM di build"
  default     = 4
}

variable "memory" {
  type        = number
  description = "RAM in MB della VM di build"
  default     = 8192
}

# ── SSH access durante la build ───────────────────────────────────────────────
variable "ssh_password" {
  type        = string
  sensitive   = true
  description = "Password root impostata dall'autoinstall, usata da Packer per connettersi"
  default     = "packer"
}

# ── Storage ─────────────────────────────────────────────────────────────────
variable "iso_storage_pool" {
  type        = string
  description = "Storage pool Proxmox per le ISO scaricate"
  default     = "local"
}

variable "template_storage_pool" {
  type        = string
  description = "Storage pool Proxmox per il disco template finale"
  default     = "local-lvm"
}
