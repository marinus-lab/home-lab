resource "proxmox_virtual_environment_vm" "this" {
  name        = var.name
  description = var.description
  node_name   = var.proxmox_node
  vm_id       = var.vm_id
  tags        = var.tags
  on_boot     = true

  # ── Clone dal template Packer ────────────────────────────────────────────────
  clone {
    vm_id   = var.template_vm_id
    full    = true # clone completo — obbligatorio con dischi raw/LVM
    retries = 3
  }

  # ── QEMU Guest Agent ─────────────────────────────────────────────────────────
  # Deve essere attivo nel template (abilitato da Packer/Ansible).
  # Proxmox lo usa per ottenere l'IP della VM e per gli shutdown ordinati.
  agent {
    enabled = true
    trim    = true # abilita TRIM/discard tramite l'agente
  }

  # ── CPU ──────────────────────────────────────────────────────────────────────
  cpu {
    cores   = var.cores
    sockets = 1
    type    = "x86-64-v2-AES" # compatibile con Ubuntu 22.04+, supporta AES-NI
  }

  # ── RAM ──────────────────────────────────────────────────────────────────────
  memory {
    dedicated = var.memory
  }

  # ── Disco ────────────────────────────────────────────────────────────────────
  # dynamic: se disk_size = 0 non crea il blocco (clone preserva la size del template).
  # Se disk_size > 0, ridimensiona dopo il clone (deve essere >= template size, Proxmox
  # non supporta shrink).
  dynamic "disk" {
    for_each = var.disk_size > 0 ? [1] : []
    content {
      datastore_id = var.storage_pool
      interface    = "scsi0"
      size         = var.disk_size
      discard      = "on"
      iothread     = true
      file_format  = "raw"
    }
  }

  # ── Rete ─────────────────────────────────────────────────────────────────────
  network_device {
    bridge   = var.network_bridge
    model    = "virtio"
    firewall = false
  }

  # ── Cloud-init (initialization) ───────────────────────────────────────────────
  # Configura la VM al primo boot: IP statico, hostname, chiave SSH pubblica.
  # Funziona grazie al drive cloud-init aggiunto da Packer al template.
  initialization {
    datastore_id = var.storage_pool

    ip_config {
      ipv4 {
        address = "${var.ip_address}/${var.cidr_prefix}"
        gateway = var.gateway
      }
    }

    user_account {
      username = "ubuntu"
      keys     = [var.ssh_public_key]
    }

    dns {
      servers = var.dns_servers
      domain  = var.domain
    }
  }

  operating_system {
    type = "l26"
  }

  boot_order = ["scsi0"]

  lifecycle {
    # Evita che Terraform tenti di aggiornare le SSH key ad ogni plan
    # dopo il provisioning iniziale.
    ignore_changes = [
      initialization[0].user_account[0].keys,
    ]
  }
}
