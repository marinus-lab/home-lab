packer {
  required_plugins {
    proxmox = {
      version = ">= 1.1.3"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

locals {
  iso_filename = "ubuntu-22.04-live-server-amd64.iso"
  vm_name      = "ubuntu-22.04-base"
}

source "proxmox-iso" "ubuntu" {
  # ── Connessione Proxmox ─────────────────────────────────────────────────────
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_token_id
  token                    = var.proxmox_token_secret
  insecure_skip_tls_verify = true
  node                     = var.proxmox_node

  # ── Identità template ───────────────────────────────────────────────────────
  vm_id                = var.vm_id
  vm_name              = local.vm_name
  template_name        = local.vm_name
  template_description = "Ubuntu 22.04 LTS base — built by Packer on ${formatdate("YYYY-MM-DD", timestamp())}"
  os                   = "l26"
  qemu_agent           = true

  # ── ISO ─────────────────────────────────────────────────────────────────────
  iso_url          = "https://releases.ubuntu.com/22.04/${local.iso_filename}"
  iso_checksum     = "file:https://releases.ubuntu.com/22.04/SHA256SUMS"
  iso_storage_pool = var.iso_storage_pool
  unmount_iso      = true

  # ── CPU e RAM ───────────────────────────────────────────────────────────────
  cores  = var.cores
  memory = var.memory

  # ── Disco ───────────────────────────────────────────────────────────────────
  scsi_controller = "virtio-scsi-pci"
  disks {
    type         = "scsi"
    disk_size    = var.disk_size
    storage_pool = var.template_storage_pool
    format       = "raw"   # raw per LVM; usare "qcow2" per storage NFS/ZFS
    discard      = true
    io_thread    = true
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
  name    = "ubuntu-22.04"
  sources = ["source.proxmox-iso.ubuntu"]

  # Aggiornamento sistema + cleanup apt
  provisioner "shell" {
    scripts         = ["scripts/install-tools.sh"]
    execute_command = "bash {{.Path}}"
  }

  # Preparazione template: locale, qemu-guest-agent, cloud-init reset, SSH keys
  provisioner "ansible" {
    playbook_file    = "../ansible/playbooks/base.yml"
    extra_arguments  = ["--extra-vars", "packer_build=true"]
    ansible_env_vars = ["ANSIBLE_HOST_KEY_CHECKING=False"]
  }
}
