source "proxmox-iso" "ubuntu_2204" {
  # ── Connessione Proxmox ─────────────────────────────────────────────────────
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_token_id
  token                    = var.proxmox_token_secret
  insecure_skip_tls_verify = true
  node                     = var.proxmox_node

  # ── Identità template ───────────────────────────────────────────────────────
  vm_id                = var.vm_id_ubuntu_2204
  vm_name              = "ubuntu-22.04-base"
  template_name        = "ubuntu-22.04-base"
  template_description = "Ubuntu 22.04 LTS base — built by Packer on ${formatdate("YYYY-MM-DD", timestamp())}"
  os                   = "l26"
  qemu_agent           = true

  # ── ISO ─────────────────────────────────────────────────────────────────────
  boot_iso {
    iso_file  = "${var.iso_storage_pool}:iso/ubuntu-22.04.5-live-server-amd64.iso"
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
    format       = "raw"   # raw per LVM; usare "qcow2" per storage NFS/ZFS
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

  # ── HTTP server per l'autoinstall ────────────────────────────────────────────
  # Packer avvia un server HTTP locale; la VM ci accede durante il boot.
  # Assicurarsi che il bastion sia raggiungibile dalla rete delle VM Proxmox.
  http_directory    = "http"
  http_bind_address = "0.0.0.0"

  # ── Boot ────────────────────────────────────────────────────────────────────
  # 'c' apre la command-line GRUB; carichiamo il kernel passando i parametri
  # autoinstall e l'URL del server HTTP di Packer.
  # net.ifnames=0 → interfaccia di rete = eth0 (coerente con user-data.tpl)
  boot_wait = "5s"
  boot_command = [
    "c<wait3>",
    "linux /casper/vmlinuz --- autoinstall net.ifnames=0 biosdevname=0 ds=nocloud-net\\;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/<enter><wait5>",
    "initrd /casper/initrd<enter><wait5>",
    "boot<enter>"
  ]

  # ── SSH ─────────────────────────────────────────────────────────────────────
  # Root abilitato dall'autoinstall tramite late-commands
  ssh_username = "root"
  ssh_password = var.ssh_password
  ssh_timeout  = "40m"
  ssh_pty      = true
}

build {
  name    = "ubuntu-2204"
  sources = ["source.proxmox-iso.ubuntu_2204"]

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
      "-v",
    ]
  }
}
