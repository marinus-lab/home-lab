#_preseed_V1
### Debian 13 (Trixie) preseed configuration for Packer automation

### Localization
d-i debian-installer/locale string en_US.UTF-8
d-i console-setup/ask_detect boolean false
d-i keyboard-configuration/xkb-keymap select it
d-i time/zone string Europe/Rome
d-i clock-setup/utc boolean true
d-i clock-setup/ntp boolean true

### Network
d-i netcfg/choose_interface select auto
d-i netcfg/dhcp_timeout string 30
d-i netcfg/dhcp_failed note
d-i netcfg/get_hostname string unassigned-hostname
d-i netcfg/get_domain string unassigned-domain
d-i hw-detect/load_firmware boolean false

### Mirror
d-i mirror/country string manual
d-i mirror/http/hostname string http.us.debian.org
d-i mirror/http/directory string /debian
d-i mirror/http/proxy string

### Account setup
d-i passwd/root-login boolean true
d-i passwd/root-password-crypted password %%ROOT_PASSWORD_HASH%%
d-i passwd/make-user boolean true
d-i passwd/user-fullname string Debian User
d-i passwd/username string debian
d-i passwd/user-password-crypted password %%DEBIAN_PASSWORD_HASH%%
d-i passwd/user-default-groups string sudo audio cdrom video

### Partitioning — LVM + XFS
d-i partman-auto/disk string /dev/sda
d-i partman-auto/method string lvm
d-i partman-lvm/device_remove_lvm boolean true
d-i partman-md/device_remove_md boolean true
d-i partman-lvm/confirm boolean true
d-i partman-lvm/confirm_nooverwrite boolean true
d-i partman-auto/choose_recipe select boot-root

# Expert recipe: /boot XFS 1GB, root XFS LVM (rest via VG vg00), swap LVM 1GB
d-i partman-auto/expert_recipe string \
      boot-root :: \
              1000 1000 1000 xfs \
                      $primary{ } $bootable{ } \
                      method{ format } format{ } \
                      use_filesystem{ } filesystem{ xfs } \
                      mountpoint{ /boot } \
              . \
              500 10000 -1 xfs \
                      method{ lvm } \
                      vg_name{ vg00 } \
              . \
              500 8000 -1 xfs \
                      $lvmok{ } \
                      in_vg{ vg00 } \
                      lv_name{ root } \
                      method{ format } format{ } \
                      use_filesystem{ } filesystem{ xfs } \
                      mountpoint{ / } \
              . \
              512 1024 1024 linux-swap \
                      $lvmok{ } \
                      in_vg{ vg00 } \
                      lv_name{ swap } \
                      method{ swap } format{ } \
              .

d-i partman-partitioning/confirm_write_new_label boolean true
d-i partman/choose_partition select finish
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true

### Base system
d-i base-installer/install-recommends boolean false

### Apt
d-i apt-setup/cdrom/set-first boolean false
d-i apt-setup/use_mirror boolean true
d-i apt-setup/services-select multiselect security, updates

### Package selection
tasksel tasksel/first multiselect standard
d-i pkgsel/include string openssh-server qemu-guest-agent cloud-init cloud-utils curl wget git vim python3 python3-pip xfsprogs
d-i pkgsel/install-language-support boolean false
d-i pkgsel/upgrade select none

### Boot loader — GRUB on /dev/sda
d-i grub-installer/only_debian boolean true
d-i grub-installer/bootdev string /dev/sda

### Finishing up
d-i finish-install/reboot_in_progress note

### Early command — debug (scrive su console se il preseed è caricato)
d-i preseed/early_command string \
    echo "PRESEED-LOADED" > /dev/console

### Late commands — enable services, SSH, sudo
d-i preseed/late_command string \
    in-target systemctl enable qemu-guest-agent ; \
    in-target systemctl enable ssh ; \
    in-target sh -c "sed -i 's/^#\\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config" ; \
    in-target sh -c "sed -i 's/^#\\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config" ; \
    in-target sh -c "echo 'debian ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/debian" ; \
    in-target chmod 0440 /etc/sudoers.d/debian ; \
    in-target cloud-init clean --logs --seed
