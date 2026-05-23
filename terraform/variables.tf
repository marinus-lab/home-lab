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

variable "k8s_subnet" {
  type        = string
  description = "Subnet del cluster Kubernetes in notazione CIDR  (es. 192.168.1.0/24)"
  default     = "192.168.1.0/24"
}

variable "k8s_gateway" {
  type        = string
  description = "Gateway della subnet Kubernetes"
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
  description = "Path alla chiave pubblica SSH iniettata nelle VM via cloud-init"
  default     = "~/.ssh/id_rsa.pub"
}

# ── Storage ────────────────────────────────────────────────────────────────────
variable "storage_pool" {
  type        = string
  description = "Storage pool Proxmox per dischi e drive cloud-init"
  default     = "local-lvm"
}

# ── Control plane (master) ─────────────────────────────────────────────────────
variable "control_plane_count" {
  type        = number
  description = "Numero di nodi control plane  (1 = minimal, 3 = HA)"
  default     = 1

  validation {
    condition     = contains([1, 3], var.control_plane_count)
    error_message = "Il control plane deve essere composto da 1 nodo (minimal) o 3 nodi (HA)."
  }
}

variable "master_vm_id_start" {
  type        = number
  description = "VM ID del primo nodo master  (i successivi sono incrementali)"
  default     = 201
}

variable "master_ip_start" {
  type        = number
  description = "Ultimo ottetto IP del primo master  (es. 210 → 192.168.1.210)"
  default     = 210
}

variable "master_cpu_cores" {
  type        = number
  description = "Core CPU per ogni nodo master"
  default     = 2
}

variable "master_memory" {
  type        = number
  description = "RAM in MB per ogni nodo master"
  default     = 2048
}

variable "master_disk_size" {
  type        = number
  description = "Dimensione disco in GB per ogni nodo master"
  default     = 30
}

# ── Worker ─────────────────────────────────────────────────────────────────────
variable "worker_count" {
  type        = number
  description = "Numero di nodi worker"
  default     = 2
}

variable "worker_vm_id_start" {
  type        = number
  description = "VM ID del primo nodo worker"
  default     = 211
}

variable "worker_ip_start" {
  type        = number
  description = "Ultimo ottetto IP del primo worker  (es. 220 → 192.168.1.220)"
  default     = 220
}

variable "worker_cpu_cores" {
  type        = number
  description = "Core CPU per ogni nodo worker"
  default     = 4
}

variable "worker_memory" {
  type        = number
  description = "RAM in MB per ogni nodo worker"
  default     = 4096
}

variable "worker_disk_size" {
  type        = number
  description = "Dimensione disco in GB per ogni nodo worker"
  default     = 50
}
