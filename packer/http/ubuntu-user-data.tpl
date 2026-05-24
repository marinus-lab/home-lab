#cloud-config
autoinstall:
  version: 1

  # ── Lingua e tastiera ────────────────────────────────────────────────────────
  locale: en_US.UTF-8
  timezone: Europe/Rome
  keyboard:
    layout: it
    variant: ''

  # ── Rete ────────────────────────────────────────────────────────────────────
  # eth0: nome fisso grazie ai parametri kernel net.ifnames=0 biosdevname=0
  network:
    network:
      version: 2
      ethernets:
        eth0:
          dhcp4: true
          dhcp-identifier: mac

  # ── Utente principale ────────────────────────────────────────────────────────
  # Password generata da build.sh con: openssl passwd -6
  identity:
    hostname: ubuntu-base
    username: ubuntu
    password: "%%UBUNTU_PASSWORD_HASH%%"

  # ── SSH ──────────────────────────────────────────────────────────────────────
  ssh:
    install-server: true
    allow-pw: true
    authorized-keys: []

  # ── Pacchetti installati durante il setup ────────────────────────────────────
  packages:
    - qemu-guest-agent
    - cloud-init
    - curl
    - wget
    - git
    - vim
    - python3
    - python3-pip
    - apt-transport-https
    - ca-certificates
    - gnupg
    - lsb-release

  # ── Storage: LVM semplice sull'intero disco ──────────────────────────────────
  storage:
    layout:
      name: lvm

  # ── Comandi post-installazione ───────────────────────────────────────────────
  late-commands:
    # Abilita login root con password per Packer
    - "curtin in-target -- bash -c \"echo 'root:%%ROOT_PASSWORD%%' | chpasswd\""
    - "sed -i 's/^#\\?PermitRootLogin.*/PermitRootLogin yes/' /target/etc/ssh/sshd_config"
    - "sed -i 's/^#\\?PasswordAuthentication.*/PasswordAuthentication yes/' /target/etc/ssh/sshd_config"
    # Sudo passwordless per l'utente ubuntu
    - "echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /target/etc/sudoers.d/ubuntu"
    - "chmod 0440 /target/etc/sudoers.d/ubuntu"
    # Avvia qemu-guest-agent al boot (necessario per Proxmox/Terraform)
    - "curtin in-target -- systemctl enable qemu-guest-agent"

  updates: security
  shutdown: reboot
