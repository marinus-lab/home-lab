# ── Identità VM ───────────────────────────────────────────────────────────────
variable "name" {
  type        = string
  description = "Nome della VM (es. k8s-master-1)"
}

variable "description" {
  type        = string
  description = "Descrizione mostrata nell'interfaccia Proxmox"
  default     = ""
}

variable "tags" {
  type        = list(string)
  description = "Tag Proxmox associati alla VM"
  default     = []
}

# ── Proxmox ───────────────────────────────────────────────────────────────────
variable "proxmox_node" {
  type        = string
  description = "Nome del nodo Proxmox"
}

variable "vm_id" {
  type        = number
  description = "VM ID univoco su Proxmox"
}

variable "template_vm_id" {
  type        = number
  description = "VM ID del template sorgente (prodotto da Packer)"
}

# ── Risorse hardware ──────────────────────────────────────────────────────────
variable "cores" {
  type        = number
  description = "Numero di core CPU"
}

variable "memory" {
  type        = number
  description = "RAM in MB"
}

variable "disk_size" {
  type        = number
  description = "Dimensione disco in GB (se > template, viene esteso)"
}

# ── Storage ───────────────────────────────────────────────────────────────────
variable "storage_pool" {
  type        = string
  description = "Storage pool Proxmox per il disco e il drive cloud-init"
}

# ── Rete ──────────────────────────────────────────────────────────────────────
variable "network_bridge" {
  type        = string
  description = "Bridge di rete Proxmox"
}

variable "ip_address" {
  type        = string
  description = "IP statico della VM (senza prefisso CIDR, es. 192.168.1.210)"
}

variable "cidr_prefix" {
  type        = string
  description = "Prefisso CIDR della subnet (es. '24')"
}

variable "gateway" {
  type        = string
  description = "Gateway di default"
}

variable "dns_servers" {
  type        = list(string)
  description = "Lista server DNS"
}

variable "domain" {
  type        = string
  description = "Dominio di ricerca DNS"
}

# ── SSH ───────────────────────────────────────────────────────────────────────
variable "ssh_public_key" {
  type        = string
  description = "Chiave pubblica SSH iniettata via cloud-init nell'utente ubuntu"
}
