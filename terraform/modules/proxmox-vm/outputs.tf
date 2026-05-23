output "ip_address" {
  description = "IP statico della VM (impostato via cloud-init)"
  value       = var.ip_address
}

output "name" {
  description = "Nome della VM"
  value       = proxmox_virtual_environment_vm.this.name
}

output "vm_id" {
  description = "VM ID su Proxmox"
  value       = proxmox_virtual_environment_vm.this.vm_id
}
