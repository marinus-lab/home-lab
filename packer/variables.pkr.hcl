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

# ── Ubuntu ISO ────────────────────────────────────────────────────────────────
variable "ubuntu_version" {
  type        = string
  description = "Versione Ubuntu da utilizzare (es. 22.04)"
  default     = "22.04"
}

# ── Template VM ───────────────────────────────────────────────────────────────
variable "vm_id" {
  type        = number
  description = "VM ID Proxmox per il template"
  default     = 9000
}

variable "storage_pool" {
  type        = string
  description = "Storage pool Proxmox per disco e drive cloud-init"
  default     = "local-lvm"
}

variable "network_bridge" {
  type        = string
  description = "Bridge di rete Proxmox"
  default     = "vmbr0"
}

variable "disk_size" {
  type        = string
  description = "Dimensione disco del template"
  default     = "20G"
}

variable "cores" {
  type        = number
  description = "Core CPU della VM di build"
  default     = 2
}

variable "memory" {
  type        = number
  description = "RAM in MB della VM di build"
  default     = 2048
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
