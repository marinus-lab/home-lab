# ── Connessione Proxmox ────────────────────────────────────────────────────────
variable "proxmox_url" {
  type        = string
  description = "URL API Proxmox"
}

variable "proxmox_token_id" {
  type        = string
  description = "Token ID Proxmox"
}

variable "proxmox_token_secret" {
  type        = string
  sensitive   = true
  description = "Token secret UUID Proxmox"
}

variable "proxmox_node" {
  type        = string
  description = "Nome del nodo Proxmox"
}

# ── VM ─────────────────────────────────────────────────────────────────────────
variable "vm_name" {
  type        = string
  description = "Nome della VM"
}

variable "vm_id" {
  type        = number
  description = "VM ID univoco su Proxmox"
}

variable "template_vm_id" {
  type        = number
  description = "VM ID del template Packer da cui clonare"
}

# ── Risorse hardware ───────────────────────────────────────────────────────────
variable "cores" {
  type        = number
  description = "Core CPU"
}

variable "memory" {
  type        = number
  description = "RAM in MB"
}

variable "disk_size" {
  type        = number
  description = "Dimensione disco in GB"
}

# ── Storage ────────────────────────────────────────────────────────────────────
variable "storage_pool" {
  type        = string
  description = "Storage pool Proxmox"
}

# ── Rete ───────────────────────────────────────────────────────────────────────
variable "network_bridge" {
  type        = string
  description = "Bridge di rete Proxmox"
  default     = "vmbr0"
}

variable "ip_address" {
  type        = string
  description = "IP statico della VM (senza CIDR)"
}

variable "cidr_prefix" {
  type        = string
  description = "Prefisso CIDR (es. 24)"
}

variable "gateway" {
  type        = string
  description = "Gateway di default"
}

variable "dns_servers" {
  type        = list(string)
  description = "Server DNS"
}

variable "domain" {
  type        = string
  description = "Dominio di ricerca DNS"
  default     = "homelab.local"
}

# ── SSH ────────────────────────────────────────────────────────────────────────
variable "ssh_public_key_path" {
  type        = string
  description = "Path alla chiave pubblica SSH"
  default     = "~/.ssh/id_rsa.pub"
}
