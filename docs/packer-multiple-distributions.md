# Packer — Building Linux Templates (Ubuntu 22.04 / 24.04 / Rocky 9)

Guida per buildare template VM su Proxmox usando Packer con supporto a multiple distribuzioni Linux.

---

## Distribuzioni supportate

| Distribuzione | Versione | Installer | Cloud-init |
|---------------|----------|-----------|-----------|
| Ubuntu LTS | 22.04 | Debian Installer (autoinstall) | ✅ Nativo |
| Ubuntu LTS | 24.04 | Debian Installer (autoinstall) | ✅ Nativo |
| Rocky Linux | 9.x | Anaconda (Kickstart) | ✅ Package |

Tutte le distribuzioni includono:
- **qemu-guest-agent** — Per interop con Proxmox/Terraform
- **cloud-init** — Per personalizzazione al boot via Terraform
- **Pacchetti base** — curl, wget, git, vim, python3, pip

---

## Prerequisiti

```bash
# Verificare che Packer sia installato
packer version

# Variabili di ambiente richieste (da terraform.auto.tfvars)
export PROXMOX_URL="https://192.168.0.93:8006/api2/json"
export PROXMOX_TOKEN_ID="automation@pve!packer"
export PROXMOX_TOKEN_SECRET="xxxxx-xxxxx-xxxxx-xxxxx"
```

Queste variabili vengono lette da `packer.pkrvars.hcl` generato da `init-project.sh`.

---

## Build interattivo

```bash
cd packer
./build.sh
```

Lo script chiede interattivamente quale distribuzione buildare:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  SELEZIONE DISTRIBUZIONE LINUX
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Quali template desideri buildare?
  1) Ubuntu 22.04 LTS
  2) Ubuntu 24.04 LTS
  3) Rocky Linux 9
  4) Tutti (22.04 + 24.04 + Rocky 9)

Seleziona (1-4):
```

---

## Build da linea di comando

```bash
# Build una singola distribuzione
./build.sh ubuntu-22.04
./build.sh ubuntu-24.04
./build.sh rocky-9

# Build tutte e tre
./build.sh ubuntu-22.04 && ./build.sh ubuntu-24.04 && ./build.sh rocky-9
```

---

## Personalizzazione

### Password utenti

Personalizza le password durante la build:

```bash
# Ubuntu
UBUNTU_PASSWORD="my-ubuntu-pass" ROOT_PASSWORD="my-root-pass" ./build.sh ubuntu-24.04

# Rocky
ROCKY_PASSWORD="my-rocky-pass" ROOT_PASSWORD="my-root-pass" ./build.sh rocky-9
```

**Default:**
- Ubuntu user: `ubuntu`
- Rocky user: `rocky`
- Root: `packer`

### Variabili Packer

Personalizza risorse VM:

```bash
# Aumenta CPU e RAM
PACKER_ARGS="-var cores=4 -var memory=4096" ./build.sh ubuntu-24.04

# Cambia nodo Proxmox
PACKER_ARGS="-var proxmox_node=pve2" ./build.sh rocky-9

# Cambia disk size
PACKER_ARGS="-var disk_size=30G" ./build.sh ubuntu-22.04
```

Variabili disponibili (in `variables.pkr.hcl`):
- `proxmox_node` (default: `pve`)
- `vm_id` (default: `9000`)
- `cores` (default: `2`)
- `memory` (default: `2048` MB)
- `disk_size` (default: `20G`)
- `storage_pool` (default: `local-lvm`)

---

## Struttura file

```
packer/
├── variables.pkr.hcl              # Variabili comuni Packer
├── ubuntu-22.04.pkr.hcl           # Build Ubuntu 22.04
├── ubuntu-24.04.pkr.hcl           # Build Ubuntu 24.04
├── rocky-9.pkr.hcl                # Build Rocky 9
├── build.sh                        # Script build interattivo
├── scripts/
│   └── install-tools.sh            # Post-build: aggiornamenti sistema
└── http/
    ├── meta-data                   # Cloud-init metadata (vuoto)
    ├── ubuntu-user-data.tpl        # Cloud-init config per Ubuntu
    └── rocky-ks.cfg.tpl            # Kickstart per Rocky Linux
```

---

## Flusso di build

### Ubuntu (22.04 / 24.04)

```
1. build.sh genera http/user-data da http/ubuntu-user-data.tpl
   ├── Sostituisce hash password %%UBUNTU_PASSWORD_HASH%%
   └── Sostituisce hash password root %%ROOT_PASSWORD%%

2. Packer scarica ISO Ubuntu dal mirror ufficiale

3. Avvia VM Proxmox con ISO

4. Kernel boot con parametri autoinstall (cloud-init)
   └── Scarica http/user-data da Packer HTTP server

5. Debian Installer esegue autoinstall (fully automated)

6. VM reboota, Packer si connette via SSH (root)

7. Esegue post-provisioning:
   ├── shell script (install-tools.sh) — aggiornamenti apt
   └── Ansible playbook (base.yml) — configurazione template

8. Cloud-init reset (per Terraform clone)

9. VM converge in template (VMID 9000, immutabile)
```

### Rocky Linux 9

```
1. build.sh genera http/rocky-ks.cfg da http/rocky-ks.cfg.tpl
   ├── Sostituisce hash password root %%ROOT_PASSWORD%%
   └── Sostituisce hash password rocky %%ROCKY_PASSWORD_HASH%%

2. Packer scarica ISO Rocky da mirror ufficiale

3. Avvia VM Proxmox con ISO

4. Kernel boot con parametri Anaconda
   └── Carica http/rocky-ks.cfg da Packer HTTP server

5. Anaconda installer esegue kickstart (fully automated)

6. VM reboota, Packer si connette via SSH (root)

7. Esegue post-provisioning:
   ├── shell script (install-tools.sh) — aggiornamenti yum
   └── Ansible playbook (base.yml) — configurazione template

8. Cloud-init reset (per Terraform clone)

9. VM converge in template (VMID 9000, immutabile)
```

---

## Verifica build

Dopo la build, verifica il template su Proxmox:

```bash
# Via API Proxmox
curl -k -X GET \
  "https://192.168.0.93:8006/api2/json/nodes/pve/qemu/9000/status/current" \
  -H "Authorization: PVEAPIToken=automation@pve!packer=xxxxx"

# Via CLI Proxmox
ssh root@proxmox "pvesh get /nodes/pve/qemu/9000/status/current"
```

Attributi attesi:
- **name**: `ubuntu-22.04-base` / `ubuntu-24.04-base` / `rocky-9-base`
- **vmid**: `9000`
- **status**: `stopped`
- **template**: `1` (is template)

---

## Troubleshooting

### "ISO download failed"

L'URL del mirror non è raggiungibile o il checksum non corrisponde.

```bash
# Verifica connessione
curl -I https://releases.ubuntu.com/24.04/ubuntu-24.04-live-server-amd64.iso

# Scarica ISO manualmente e specifica il path locale
PACKER_ARGS="-var iso_url=/tmp/ubuntu-24.04.iso" ./build.sh ubuntu-24.04
```

### "SSH timeout"

La VM non è raggiungibile via SSH dopo il boot.

Cause comuni:
- Rete non configurata (cloud-init non è partito)
- Firewall blocca SSH
- Bastion non raggiunge la rete Proxmox

```bash
# Debug: accedi a Proxmox console e verifica:
# 1. IP address: ip addr
# 2. SSH service: systemctl status sshd
# 3. iptables: iptables -L
```

### "Cloud-init not available"

Cloud-init non è installato nel template.

```bash
# Verifica in Proxmox console
cloud-init --version

# Se manca, aggiungi il package al kickstart (Rocky) o user-data (Ubuntu)
```

### "Checksum mismatch"

Il file SHA256SUMS non è raggiungibile.

```bash
# Usa checksum manuale invece di file URL
# In .pkr.hcl, cambia:
#   iso_checksum = "file:https://..."
# Con:
#   iso_checksum = "sha256:abc123def456..."
```

---

## Performance tips

1. **Aumenta CPU/RAM durante build** — Accelera compilazione
   ```bash
   PACKER_ARGS="-var cores=4 -var memory=4096" ./build.sh ubuntu-24.04
   ```

2. **Usa storage pool veloce** — Preferisci SSD se disponibile
   ```bash
   PACKER_ARGS="-var storage_pool=ssd-lvm" ./build.sh rocky-9
   ```

3. **Parallelizza build multiple** — Se Proxmox supporta 2+ VM contemporanee
   ```bash
   # Terminal 1
   ./build.sh ubuntu-22.04

   # Terminal 2
   ./build.sh ubuntu-24.04
   ```

4. **Caching ISO** — Una volta scaricato, Packer lo cacheizza
   - Ubicazione: `~/.packer.d/` o `/tmp/packer_cache/`

---

## Dopo il build

Una volta che il template è pronto:

```bash
# 1. Terraform clona il template e crea le VM K8s
cd ../terraform
terraform apply

# 2. Kubespray provisiona Kubernetes
cd ../kubespray
./deploy.sh
```

---

## Note di sicurezza

### Credenziali nel template

**Le password di build NON persistono nel template finale** perché:

1. Packer imposta password di root per SSH post-build
2. Dopo completamento, cloud-init resetta tutte le credenziali
3. Terraform inietta nuove credenziali via cloud-init user-data

### SSH Keys

Non salvare private SSH keys nel template. Invece:

1. Configura public key in cloud-init user-data (Terraform)
2. Terraform inietta `authorized_keys` per root

```bash
# In cloud-init (Terraform):
ssh-authorized-keys:
  - ssh-rsa AAAAB3Nza... user@bastion
```

---

## Riferimenti

- [Packer Proxmox Provider](https://github.com/hashicorp/packer-plugin-proxmox)
- [Ubuntu Autoinstall](https://ubuntu.com/server/docs/install/autoinstall)
- [Rocky Linux Kickstart](https://rocky.readthedocs.io/en/latest/guides/installation/)
- [Cloud-init Documentation](https://cloud-init.io/)
