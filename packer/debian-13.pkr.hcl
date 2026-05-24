source "proxmox-iso" "debian_13" {
  # ── Connessione Proxmox ─────────────────────────────────────────────────────
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_token_id
  token                    = var.proxmox_token_secret
  insecure_skip_tls_verify = true
  node                     = var.proxmox_node

  # ── Identità template ───────────────────────────────────────────────────────
  vm_id                = var.vm_id_debian_13
  vm_name              = "debian-13-base"
  template_name        = "debian-13-base"
  template_description = "Debian 13 Trixie base — built by Packer on ${formatdate("YYYY-MM-DD", timestamp())}"
  os                   = "l26"
  qemu_agent           = true

  # ── ISO ─────────────────────────────────────────────────────────────────────
  boot_iso {
    iso_file  = "${var.iso_storage_pool}:iso/debian-13.5.0-amd64-netinst.iso"
    unmount   = true
  }

  # ── CPU e RAM ───────────────────────────────────────────────────────────────
  cores    = var.cores
  memory   = var.memory
  cpu_type = "host"

  # ── Disco ───────────────────────────────────────────────────────────────────
  scsi_controller = "virtio-scsi-single"
  disks {
    type         = "scsi"
    disk_size    = var.disk_size
    storage_pool = var.template_storage_pool
    format       = "raw"
    discard      = true
    io_thread    = true
    cache_mode   = "writeback"
  }

  # ── Rete ────────────────────────────────────────────────────────────────────
  network_adapters {
    model  = "virtio"
    bridge = var.network_bridge
  }

  # ── Drive cloud-init (usato da Terraform dopo il clone) ─────────────────────
  cloud_init              = true
  cloud_init_storage_pool = var.template_storage_pool

  # ── HTTP server per il preseed ──────────────────────────────────────────────
  http_directory    = "http"
  http_bind_address = "0.0.0.0"

  # ── Boot: Debian installer con preseed ──────────────────────────────────────
  # ESC×2 → prompt boot:. Poi "auto http://URL" basta per avviare il preseed.
  boot_wait = "15s"
  boot_command = [
    "<esc><wait>",
    "<esc><wait>",
    "auto http://{{ .HTTPIP }}:{{ .HTTPPort }}/debian-preseed.cfg<enter>"
  ]

  # ── SSH ─────────────────────────────────────────────────────────────────────
  ssh_username = "root"
  ssh_password = var.ssh_password
  ssh_timeout  = "40m"
  ssh_pty      = true
}

build {
  name    = "debian-13"
  sources = ["source.proxmox-iso.debian_13"]

  # Aggiornamento sistema + cleanup apt
  provisioner "shell" {
    scripts         = ["scripts/install-tools.sh"]
    execute_command = "bash {{.Path}}"
  }

  # Preparazione template: locale, qemu-guest-agent, cloud-init reset, SSH keys
  provisioner "ansible" {
    playbook_file = "../ansible/playbooks/base.yml"
    user          = "root"
    use_proxy     = false

    ansible_env_vars = [
      "ANSIBLE_HOST_KEY_CHECKING=False",
    ]

    extra_arguments = [
      "--extra-vars", "{\"packer_build\":true}",
      "--extra-vars", "ansible_password=${var.ssh_password}",
      "--ssh-extra-args", "-o PreferredAuthentications=password,keyboard-interactive,publickey -o PasswordAuthentication=yes -o UserKnownHostsFile=/dev/null",
      "-vvv",
    ]
  }
}
