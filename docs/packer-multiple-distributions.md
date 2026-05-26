# Packer — Building Linux Templates (Ubuntu 22.04 / 24.04 / Debian 13 / Rocky 9)

Guida per buildare template VM su Proxmox usando Packer con supporto a multiple distribuzioni Linux.

---

## Distribuzioni supportate

| Distribuzione | Versione | Installer | Cloud-init |
|---------------|----------|-----------|-----------|
| Ubuntu LTS | 22.04 | Debian Installer (autoinstall) | ✅ Nativo |
| Ubuntu LTS | 24.04 | Debian Installer (autoinstall) | ✅ Nativo |
| Debian | 13 (Trixie) | Debian Installer (Preseed) | ✅ Package |
| Rocky Linux | 9.x | Anaconda (Kickstart) | ✅ Package |

Tutte le distribuzioni includono:
- **qemu-guest-agent** — **Obbligatorio**: Packer lo usa per comunicare con la VM durante la build (spegnimento, reboot, verifica stato). Senza qemu-guest-agent, Packer non riesce a gestire correttamente il ciclo di vita della VM.
- **cloud-init** — Per personalizzazione al boot via Terraform
- **cloud-utils-growpart** — Espansione partizione root al primo boot
- **Pacchetti base** — curl, wget, git, vim, python3, pip

---

## Prerequisiti

```bash
# Verificare che Packer sia installato
packer version

# Variabili di ambiente richieste (da terraform.auto.tfvars)
export PROXMOX_URL="https://192.168.1.10:8006/api2/json"
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
  4) Debian 13
  5) Tutti (22.04 + 24.04 + Rocky 9 + Debian 13)

Seleziona (1-5):
```

---

## Build da linea di comando

```bash
# Build una singola distribuzione
./build.sh ubuntu-22.04
./build.sh ubuntu-24.04
./build.sh rocky-9
./build.sh debian-13

# Build tutte e quattro
./build.sh ubuntu-22.04 && ./build.sh ubuntu-24.04 && ./build.sh rocky-9 && ./build.sh debian-13
```

---

## Debug

Per diagnosticare problemi durante la build, esegui lo script con il log di Packer abilitato:

```bash
PACKER_LOG=1 ./build.sh
```

Questo mostra tutti i dettagli interni di Packer: connessione SSH, esecuzione dei provisioner, invocazione di Ansible, e codice d'uscita di ogni comando remoto. Utile per individuare:
- Fallimenti di connessione SSH (host key mismatch, timeout)
- Errori del proxy adapter Ansible (SFTP/SCP/pipelining)
- Comandi remoti che falliscono silenziosamente

---

## Personalizzazione

### Password utenti

Personalizza le password durante la build:

```bash
# Ubuntu
UBUNTU_PASSWORD="my-ubuntu-pass" ROOT_PASSWORD="my-root-pass" ./build.sh ubuntu-24.04

# Rocky
ROCKY_PASSWORD="my-rocky-pass" ROOT_PASSWORD="my-root-pass" ./build.sh rocky-9

# Debian
DEBIAN_PASSWORD="my-debian-pass" ROOT_PASSWORD="my-root-pass" ./build.sh debian-13
```

**Default:**
- Ubuntu user: `ubuntu`
- Rocky user: `rocky`
- Debian user: `debian`
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
- `vm_id_rocky_9` (default: `9000` — VM ID per Rocky 9)
- `vm_id_ubuntu_2204` (default: `9001` — VM ID per Ubuntu 22.04)
- `vm_id_ubuntu_2404` (default: `9002` — VM ID per Ubuntu 24.04)
- `vm_id_debian_13` (default: `9003` — VM ID per Debian 13)
- `cores` (default: `4`)
- `memory` (default: `8192` MB / 8 GB)
- `disk_size` (default: `32G`)
- `template_storage_pool` (default: `local-lvm`)
- `iso_storage_pool` (default: `local`)

Per cambiare un VM ID:

```bash
# Da riga di comando
PACKER_ARGS="-var vm_id_ubuntu_2404=9010" ./build.sh ubuntu-24.04

# Oppure modifica il default in packer/variables.pkr.hcl
```

---

## Configurazione template VM

### Filesystem

Tutte le distribuzioni usano **XFS** come filesystem:

| Componente | Rocky 9 | Ubuntu 22.04 / 24.04 | Debian 13 |
|---|---|---|---|
| `/boot` | XFS (1 GB) | XFS (1 GB) | XFS (1 GB) |
| `/` (root) | XFS (partizione singola, spazio rimanente) | XFS (LVM, spazio rimanente) | XFS (LVM, spazio rimanente) |

### Cache disco

Tutte le VM di build usano **writeback** come modalità cache del disco Proxmox:

```hcl
cache_mode = "writeback"
```

Questo offre migliori prestazioni di I/O durante la build. Il template risultante mantiene la stessa configurazione.

### Locale e lingua

| Parametro | Valore |
|---|---|
| Lingua (`LANG`) | `en_US.UTF-8` |
| Formato ora (`LC_TIME`) | `en_GB.UTF-8` (24h, date DD/MM) |
| Tastiera | Italiana (`it`) |
| Timezone | `Europe/Rome` |

### Password di default

| Utente | Password | Personalizzabile via |
|---|---|---|
| root | `packer` | `ROOT_PASSWORD` |
| ubuntu (Ubuntu) | `ubuntu` | `UBUNTU_PASSWORD` |
| rocky (Rocky) | `rocky` | `ROCKY_PASSWORD` |
| debian (Debian) | `debian` | `DEBIAN_PASSWORD` |

Le password persistono **solo durante la build** Packer per consentire l'accesso SSH. Dopo il clone con Terraform, cloud-init imposta nuove credenziali.

---

## Struttura file

```
packer/
├── variables.pkr.hcl              # Variabili comuni Packer
├── ubuntu-22.04.pkr.hcl           # Build Ubuntu 22.04
├── ubuntu-24.04.pkr.hcl           # Build Ubuntu 24.04
├── debian-13.pkr.hcl              # Build Debian 13
├── rocky-9.pkr.hcl                # Build Rocky 9
├── build.sh                        # Script build interattivo
├── download-isos.sh                 # Pre-download ISO su Proxmox
├── scripts/
│   └── install-tools.sh            # Post-build: aggiornamenti sistema
└── http/
    ├── meta-data                   # Cloud-init metadata (vuoto)
    ├── ubuntu-user-data.tpl        # Cloud-init config per Ubuntu
    ├── debian-preseed.cfg.tpl      # Preseed config per Debian
    └── rocky-ks.cfg.tpl            # Kickstart per Rocky Linux
```

---

## Flusso di build

### Ubuntu (22.04 / 24.04)

```
1. build.sh genera http/ubuntu-user-data da http/ubuntu-user-data.tpl
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

9. VM converge in template (VMID 9001, immutabile)
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

### Debian 13

```
1. build.sh genera http/debian-preseed.cfg da http/debian-preseed.cfg.tpl
   ├── Sostituisce hash password root %%ROOT_PASSWORD_HASH%%
   └── Sostituisce hash password debian %%DEBIAN_PASSWORD_HASH%%

2. Packer carica ISO Debian (pre-uploadata su Proxmox)

3. Avvia VM Proxmox con ISO

4. ESC×2 al menu ISOLINUX → prompt `boot:`

5. Comando di boot: `auto url=http://<PACKER_IP>:<PORT>/debian-preseed.cfg`
   └── Sintassi scoperta sperimentalmente: `auto url=...` (NON `preseed/url=...`)
   └── L'installer ignora `preseed/url` e richiede `auto url=...` per caricare il preseed

6. Debian Installer esegue installazione preseed (fully automated)
   └── LVM + XFS, pacchetti di base, qemu-guest-agent, cloud-init

7. VM reboota, Packer si connette via SSH (root)

8. Esegue post-provisioning:
   ├── shell script (install-tools.sh) — aggiornamenti apt
   └── Ansible playbook (base.yml) — configurazione template

9. Cloud-init reset (per Terraform clone)

10. VM converge in template (VMID 9003, immutabile)
```

---

## Verifica build

Dopo la build, verifica il template su Proxmox:

```bash
# Sostituisci <VMID> con:
#   Rocky 9      → 9000
#   Ubuntu 22.04 → 9001
#   Ubuntu 24.04 → 9002
#   Debian 13    → 9003
VMID=9002

# Via API Proxmox
curl -k -X GET \
  "https://192.168.0.93:8006/api2/json/nodes/pve/qemu/${VMID}/status/current" \
  -H "Authorization: PVEAPIToken=automation@pve!packer=xxxxx"

# Via CLI Proxmox
ssh root@proxmox "pvesh get /nodes/pve/qemu/${VMID}/status/current"
```

Attributi attesi:
- **name**: `ubuntu-22.04-base` / `ubuntu-24.04-base` / `debian-13-base` / `rocky-9-base`
- **vmid**: dipende dalla distribuzione (9000, 9001, 9002, 9003)
- **status**: `stopped`
- **template**: `1` (is template)

Per cambiare i VM ID, modifica i default in `packer/variables.pkr.hcl` o usa `PACKER_ARGS`:

```bash
PACKER_ARGS="-var vm_id_ubuntu_2404=9010" ./build.sh ubuntu-24.04
```

---

## Troubleshooting

### "ISO download failed"

L'URL del mirror non è raggiungibile o il checksum non corrisponde.

```bash
# Verifica connessione
curl -I https://releases.ubuntu.com/24.04/ubuntu-24.04-live-server-amd64.iso

# Opzione 1: Scarica ISO manualmente e specifica il path locale
PACKER_ARGS="-var iso_url=/tmp/ubuntu-24.04.iso" ./build.sh ubuntu-24.04

# Opzione 2: Usa download-isos.sh per caricare ISO su Proxmox
./download-isos.sh ubuntu-24.04       # singola
./download-isos.sh all                # tutte le distribuzioni
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

### "Ansible SFTP/SCP non funziona — `sftp: Connection closed`"

Il proxy SSH del plugin ansible v1.1.4 di Packer ha alcuni bug:
- **SFTP** — prova a eseguire `/usr/lib/sftp-server -e` sulla VM, ma su Rocky/RHEL il path è `/usr/libexec/openssh/sftp-server`
- **SCP** — `scp: Connection closed` attraverso il proxy
- **Pipelining** — stdin non viene chiuso correttamente, Python resta in attesa

**Soluzione applicata** nei template — `use_proxy = false` + autenticazione via password:

```hcl
provisioner "ansible" {
    playbook_file = "../ansible/playbooks/base.yml"
    user          = "root"
    use_proxy     = false

    ansible_env_vars = [
        "ANSIBLE_HOST_KEY_CHECKING=False",
    ]

    extra_arguments = [
        "--extra-vars", "packer_build=true",
        "--extra-vars", "ansible_password=${var.ssh_password}",
        "--ssh-extra-args", "-o PreferredAuthentications=password,keyboard-interactive,publickey -o PasswordAuthentication=yes -o UserKnownHostsFile=/dev/null",
    ]
}
```

Con `use_proxy = false` Ansible si connette direttamente alla VM (non al proxy locale). Packer genera una chiave SSH temporanea in formato non compatibile con la libcrypto di sistema (`error in libcrypto`), ma Ansible esegue il fallback a password auth. Le operazioni SFTP/SCP vanno direttamente al demone SSH della VM senza intermediari.

### "Debian 13 preseed non caricato — installer interattivo"

Il template Debian 13 non riesce a caricare il preseed e l'installer parte in modalità interattiva (richiede lingua).

**Causa:** l'installer Debian 13 (Trixie) ignora il parametro `preseed/url=` tradizionale quando digitato al prompt `boot:`.

**Soluzione:** usare la sintassi `auto url=http://...`:

```
boot: auto url=http://192.168.0.219:8000/debian-preseed.cfg
```

**Dettaglio:** `auto` abilita la modalità automatica, `url=...` specifica il preseed. Non serve anteporre `install` o aggiungere `preseed/url=`. Non funziona nemmeno via CLI ISOLINUX (`c` → `linux`/`initrd`/`boot`). L'unica combinazione funzionante è ESC×2 al menu ISOLINUX + `auto url=...` + Enter.

### "VM already exists — Packer non parte"

Il VM ID della distribuzione è già occupato su Proxmox.

**Soluzione:** `build.sh` rileva automaticamente il conflitto via API Proxmox e chiede:
```
⚠️  VM 9003 (debian-13) already exists on node 'prox-dell1'
   Packer non può creare una VM con lo stesso ID.
Overwrite with -force? (y/N):
```
Rispondi `y` per eseguire con `-force` (elimina e ricrea la VM). Rispondi `n` per abortire.

Se vuoi forzare direttamente senza prompt:
```bash
PACKER_ARGS="-force" ./build.sh debian-13
```

### "Cloud-init not available"

Cloud-init non è installato nel template.

```bash
# Verifica in Proxmox console
cloud-init --version

# Se manca, aggiungi il package al kickstart (Rocky) o user-data (Ubuntu)
```

### "REMOTE HOST IDENTIFICATION HAS CHANGED"

Errore SSH quando l'IP della VM di build è già presente in `~/.ssh/known_hosts` con una chiave host diversa (tipico su build successive). SSH disabilita password auth come protezione MITM:

```
@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
Password authentication is disabled to avoid man-in-the-middle attacks.
```

**Soluzione:** nei template Packer, `--ssh-extra-args` include già `-o UserKnownHostsFile=/dev/null` per evitare il conflitto. Se il problema persiste in altri contesti:

```bash
ssh-keygen -f ~/.ssh/known_hosts -R "<IP_VM>"
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

1. **Riduci CPU/RAM se necessario** — I default (4 CPU, 8 GB RAM) sono già ottimizzati
   ```bash
   PACKER_ARGS="-var cores=2 -var memory=2048" ./build.sh ubuntu-24.04
   ```

2. **Usa storage pool veloce** — Preferisci SSD se disponibile
   ```bash
   PACKER_ARGS="-var template_storage_pool=ssd-lvm" ./build.sh rocky-9
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
terraform init
terraform apply -parallelism=2

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
- [Debian Preseed (official example)](https://www.debian.org/releases/trixie/example-preseed.txt)
- [Cloud-init Documentation](https://cloud-init.io/)
