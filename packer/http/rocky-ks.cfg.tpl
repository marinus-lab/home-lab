# Rocky Linux 9 Kickstart configuration for Packer
# Automated installation with cloud-init support

# ── Keyboard e lingua ────────────────────────────────────────────────────────
lang it_IT.UTF-8
keyboard it
timezone Europe/Rome

# ── Utente root ──────────────────────────────────────────────────────────────
rootpw --iscrypted %%ROOT_PASSWORD%%

# ── Utente principale ────────────────────────────────────────────────────────
user --name=rocky --groups=wheel --iscrypted --password=%%ROCKY_PASSWORD_HASH%%

# ── Rete ─────────────────────────────────────────────────────────────────────
network --bootproto=dhcp --onboot=yes --device=eth0 --activate

# ── Repository online (boot.iso non contiene pacchetti) ────────────────────
url --mirrorlist="https://mirrors.rockylinux.org/mirrorlist?arch=x86_64&repo=BaseOS-9"
repo --name="AppStream" --mirrorlist="https://mirrors.rockylinux.org/mirrorlist?arch=x86_64&repo=AppStream-9"

# ── Storage ──────────────────────────────────────────────────────────────────
bootloader --location=mbr --driveorder=vda
zerombr
clearpart --all --initlabel
part /boot --fstype=ext4 --size=1024
part swap --size=2048
part / --fstype=ext4 --size=1 --grow

# ── Pacchetti ────────────────────────────────────────────────────────────────
%packages
@core
@standard
qemu-guest-agent
cloud-init
curl
wget
git
vim
python3
python3-pip
%end

# ── Servizi ──────────────────────────────────────────────────────────────────
%post
# Abilita qemu-guest-agent al boot
systemctl enable qemu-guest-agent
systemctl start qemu-guest-agent

# Configura SSH per root password login
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
systemctl enable sshd

# Sudoers passwordless per rocky user
echo 'rocky ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/rocky
chmod 0440 /etc/sudoers.d/rocky

# Cloud-init: reset per ogni clone (importante per Terraform)
cloud-init clean --logs --seed
%end

# ── Post-installazione ──────────────────────────────────────────────────────
reboot
