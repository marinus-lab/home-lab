output "k3s_node_ips" {
  description = "IP dei nodi K3S"
  value       = { for k in keys(local.k3s_nodes) : k => module.k3s_node[k].ip_address }
}

output "k3s_inventory_path" {
  description = "Path all'inventory K3S generato"
  value       = local_file.k3s_inventory.filename
}

output "ssh_command_examples" {
  description = "Comandi SSH di esempio per accedere ai nodi K3S"
  value = {
    for k in keys(local.k3s_nodes) : k => "ssh ubuntu@${module.k3s_node[k].ip_address}"
  }
}
