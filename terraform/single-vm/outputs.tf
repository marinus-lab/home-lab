output "vm_name" {
  value       = module.vm.name
  description = "Nome della VM creata"
}

output "vm_id" {
  value       = module.vm.vm_id
  description = "VM ID su Proxmox"
}

output "ip_address" {
  value       = module.vm.ip_address
  description = "Indirizzo IP della VM"
}

output "ssh_command" {
  value       = "ssh ubuntu@${module.vm.ip_address}"
  description = "Comando per connettersi alla VM via SSH"
}
