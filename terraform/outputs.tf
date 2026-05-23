output "control_plane_ips" {
  description = "IP dei nodi control plane"
  value       = { for k in keys(local.control_plane_nodes) : k => module.k8s_master[k].ip_address }
}

output "worker_ips" {
  description = "IP dei nodi worker"
  value       = { for k in keys(local.worker_nodes) : k => module.k8s_worker[k].ip_address }
}

output "all_nodes" {
  description = "Mappa nome → IP di tutti i nodi del cluster"
  value = merge(
    { for k in keys(local.control_plane_nodes) : k => module.k8s_master[k].ip_address },
    { for k in keys(local.worker_nodes) : k => module.k8s_worker[k].ip_address }
  )
}

output "kubespray_inventory_path" {
  description = "Path all'inventory Kubespray generato"
  value       = local_file.kubespray_inventory.filename
}

output "ssh_command_examples" {
  description = "Comandi SSH di esempio per accedere ai nodi"
  value = {
    for name, ip in merge(
      { for k in keys(local.control_plane_nodes) : k => module.k8s_master[k].ip_address },
      { for k in keys(local.worker_nodes) : k => module.k8s_worker[k].ip_address }
    ) : name => "ssh ubuntu@${ip}"
  }
}
