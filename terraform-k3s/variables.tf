# ── Connessione Proxmox ────────────────────────────────────────────────────────
variable "proxmox_url" {
  type        = string
  description = "URL API Proxmox  (es. https://192.168.1.10:8006/api2/json)"
}

variable "proxmox_token_id" {
  type        = string
  description = "Token ID Proxmox  (es. automation@pve!terraform)"
}

variable "proxmox_token_secret" {
  type        = string
  sensitive   = true
  description = "Token secret UUID Proxmox"
}

variable "proxmox_node" {
  type        = string
  description = "Nome del nodo Proxmox su cui creare le VM"
  default     = "pve"
}

# ── Template sorgente (prodotto da Packer) ─────────────────────────────────────
variable "template_vm_id" {
  type        = number
  description = "VM ID del template Ubuntu creato da Packer"
  default     = 9000
}

# ── Rete ───────────────────────────────────────────────────────────────────────
variable "network_bridge" {
  type        = string
  description = "Bridge di rete Proxmox"
  default     = "vmbr0"
}

variable "k3s_subnet" {
  type        = string
  description = "Subnet delle VM K3S in notazione CIDR  (es. 192.168.1.0/24)"
  default     = "192.168.1.0/24"
}

variable "k3s_gateway" {
  type        = string
  description = "Gateway della subnet K3S"
  default     = "192.168.1.1"
}

variable "dns_servers" {
  type        = list(string)
  description = "Server DNS per le VM"
  default     = ["1.1.1.1", "8.8.8.8"]
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

# ── Storage ─────────────────────────────────────────────────────────────────────
variable "storage_pool" {
  type        = string
  description = "Storage pool Proxmox per dischi e drive cloud-init"
  default     = "local-lvm"
}

# ── Topologia ──────────────────────────────────────────────────────────────────
variable "k3s_count" {
  type        = number
  description = "Numero di nodi K3S"
  default     = 3
}

variable "k3s_vm_id_start" {
  type        = number
  description = "VM ID del primo nodo K3S  (i successivi sono incrementali)"
  default     = 44777
}

variable "k3s_ip_start" {
  type        = number
  description = "Ultimo ottetto IP del primo nodo K3S  (es. 160 → 192.168.1.160)"
  default     = 160
}

# ── Risorse hardware (stesse dei master K8s) ──────────────────────────────────
variable "k3s_cpu_cores" {
  type        = number
  description = "Core CPU per ogni nodo K3S"
  default     = 4
}

variable "k3s_memory" {
  type        = number
  description = "RAM in MB per ogni nodo K3S"
  default     = 16384
}

variable "k3s_disk_size" {
  type        = number
  description = "Dimensione disco in GB per ogni nodo K3S (0 = eredita dal template)"
  default     = 0
}
