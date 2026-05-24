source "proxmox-iso" "rocky" {
  # ── Connessione Proxmox ─────────────────────────────────────────────────────
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_token_id
  token                    = var.proxmox_token_secret
  insecure_skip_tls_verify = true
  node                     = var.proxmox_node

  # ── Identità template ───────────────────────────────────────────────────────
  vm_id                = var.vm_id
  vm_name              = "rocky-9-base"
  template_name        = "rocky-9-base"
  template_description = "Rocky Linux 9 base — built by Packer on ${formatdate("YYYY-MM-DD", timestamp())}"
  os                   = "l26"
  qemu_agent           = true

  # ── ISO ─────────────────────────────────────────────────────────────────────
  boot_iso {
    iso_file = "${var.iso_storage_pool}:iso/Rocky-9-latest-x86_64-boot.iso"
    unmount  = true
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

  # ── HTTP server per il kickstart ─────────────────────────────────────────────
  http_directory    = "http"
  http_bind_address = "0.0.0.0"

  # ── Boot: Anaconda installer con kickstart ──────────────────────────────────
  boot_wait = "5s"
  boot_command = [
    "<tab><wait>",
    " inst.ks=http://{{ .HTTPIP }}:{{ .HTTPPort }}/rocky-ks.cfg<enter><wait>"
  ]

  # ── SSH ─────────────────────────────────────────────────────────────────────
  # Root abilitato dal kickstart
  ssh_username = "root"
  ssh_password = var.ssh_password
  ssh_timeout  = "40m"
  ssh_pty      = true
}

build {
  name    = "rocky-9"
  sources = ["source.proxmox-iso.rocky"]

  # Aggiornamento sistema + cleanup yum
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
