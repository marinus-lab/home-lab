packer {
  required_plugins {
    proxmox = {
      version = ">= 1.1.3"
      source  = "github.com/hashicorp/proxmox"
    }
    ansible = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/ansible"
    }
  }
}

locals {
  iso_filename = "Rocky-9.4-x86_64-dvd.iso"
  vm_name      = "rocky-9-base"
}

source "proxmox-iso" "rocky" {
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
  template_description = "Rocky Linux 9 base — built by Packer on ${formatdate("YYYY-MM-DD", timestamp())}"
  os                   = "l26"
  qemu_agent           = true

  # ── ISO ─────────────────────────────────────────────────────────────────────
  iso_url          = "https://download.rockylinux.org/pub/rocky/9/isos/x86_64/${local.iso_filename}"
  iso_checksum     = "file:https://download.rockylinux.org/pub/rocky/9/isos/x86_64/CHECKSUM"
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
    format       = "raw"
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
    playbook_file    = "../ansible/playbooks/base.yml"
    extra_arguments  = ["--extra-vars", "packer_build=true"]
    ansible_env_vars = ["ANSIBLE_HOST_KEY_CHECKING=False"]
  }
}
