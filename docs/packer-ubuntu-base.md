# Packer — Build del template Ubuntu base per Proxmox

## Indice

1. [Panoramica](#panoramica)
2. [Struttura dei file](#struttura-dei-file)
3. [Flusso di build](#flusso-di-build)
4. [File di configurazione](#file-di-configurazione)
   - [variables.pkr.hcl](#variablespkrhcl)
   - [Template .pkr.hcl](#template-pkrhcl-es-ubuntu-2404pkrhcl)
   - [http/ubuntu-user-data.tpl](#httpubuntu-user-datatpl)
   - [http/meta-data](#httpmeta-data)
   - [scripts/install-tools.sh](#scriptsinstall-toolssh)
   - [ansible/playbooks/base.yml](#ansibleplaybooksbaseyml)
5. [build.sh — script di avvio](#buildsh)
6. [Autenticazione Proxmox](#autenticazione-proxmox)
7. [Come funziona l'autoinstall Ubuntu](#come-funziona-lautoinstall-ubuntu)
8. [Perché il cleanup del template è importante](#perché-il-cleanup-del-template-è-importante)
9. [Utilizzo](#utilizzo)
10. [Troubleshooting](#troubleshooting)

---

## Panoramica

Questo setup utilizza **HashiCorp Packer** per costruire template VM su Proxmox VE — supporta Ubuntu 22.04, 24.04, Debian 13 e Rocky 9. I template vengono poi usati da Terraform per clonare rapidamente le VM del cluster Kubernetes.

> **Nota:** Questo documento descrive il funzionamento generale dei template Packer. Per la procedura di build multi-distribuzione, vedi [packer-multiple-distributions.md](packer-multiple-distributions.md).

Il processo di build esegue in sequenza:

```
ISO Ubuntu  →  Autoinstall (unattended)  →  Shell provisioner  →  Ansible provisioner  →  Template Proxmox
```

Il template risultante ha queste caratteristiche:
- Ubuntu 22.04 LTS aggiornato
- `qemu-guest-agent` attivo (necessario per Proxmox/Terraform)
- Drive cloud-init collegato (Terraform lo usa per configurare IP, hostname, SSH key)
- `machine-id` e SSH host key rimossi (rigenerati univoci ad ogni clone)
- `cloud-init` resettato (si riesegue al primo boot di ogni VM clonata)

---

## Struttura dei file

```
packer/
├── variables.pkr.hcl              # Definizione di tutte le variabili
├── ubuntu-22.04.pkr.hcl           # Build Ubuntu 22.04
├── ubuntu-24.04.pkr.hcl           # Build Ubuntu 24.04
├── debian-13.pkr.hcl              # Build Debian 13
├── rocky-9.pkr.hcl                # Build Rocky 9
├── build.sh                       # Script di avvio build (interattivo)
├── download-isos.sh               # Pre-download ISO su Proxmox
├── packer.pkrvars.hcl.example     # Esempio file variabili
├── http/
│   ├── ubuntu-user-data.tpl       # Template autoinstall Ubuntu (con segnaposto password)
│   ├── debian-preseed.cfg.tpl     # Config preseed per Debian
│   ├── rocky-ks.cfg.tpl           # Kickstart per Rocky Linux
│   └── meta-data                  # File vuoto richiesto dal protocollo nocloud
└── scripts/
    └── install-tools.sh           # Script shell eseguito da Packer post-install
```

---

## Flusso di build

```
┌─────────────────────────────────────────────────────────┐
│  build.sh                                               │
│  1. Genera hash SHA-512 della password ubuntu           │
│  2. Sostituisce i segnaposto in ubuntu-user-data.tpl    │
│     → produce http/user-data                            │
│  3. packer init  (scarica i plugin proxmox + ansible)   │
│  4. packer build ubuntu-24.04.pkr.hcl (o altra distro)  │
└─────────────────────────────┬───────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────┐
│  Packer: source proxmox-iso                             │
│  - Crea VM su Proxmox via API                           │
│  - Monta ISO Ubuntu 22.04                               │
│  - Avvia server HTTP locale (porta casuale 8000-9000)   │
│  - Invia boot_command via VNC                           │
└─────────────────────────────┬───────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────┐
│  GRUB command-line (tasto 'c')                          │
│  Carica kernel con parametri:                           │
│    autoinstall                                          │
│    ds=nocloud-net;s=http://<BASTION_IP>:<PORT>/         │
│    net.ifnames=0  biosdevname=0                         │
└─────────────────────────────┬───────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────┐
│  Ubuntu Subiquity (autoinstall)                         │
│  Legge http/user-data e http/meta-data dal bastion      │
│  - Partizionamento LVM                                  │
│  - Installazione pacchetti base                         │
│  - late-commands: abilita root SSH, sudoers             │
│  - Reboot automatico al termine                         │
└─────────────────────────────┬───────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────┐
│  Packer: shell provisioner                              │
│  Esegue scripts/install-tools.sh                        │
│  - apt-get upgrade (aggiorna tutti i pacchetti)         │
│  - pulizia apt cache                                    │
└─────────────────────────────┬───────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────┐
│  Packer: ansible provisioner                            │
│  Esegue ansible/playbooks/base.yml                      │
│  (con packer_build=true)                                │
│  - Abilita qemu-guest-agent                             │
│  - Reset cloud-init                                     │
│  - Rimuove SSH host keys                                │
│  - Svuota machine-id                                    │
│  - Pulizia /tmp                                         │
└─────────────────────────────┬───────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────┐
│  Packer: conversione in template Proxmox                │
│  - Smonta ISO                                           │
│  - Converte VM → template (ID 9002 per Ubuntu 24.04)    │
│  - Template pronto per clonazione con Terraform         │
└─────────────────────────────────────────────────────────┘
```

---

## File di configurazione

### `variables.pkr.hcl`

Centralizza tutte le variabili. Ogni variabile può essere sovrascritta tramite:
- variabile d'ambiente (per le credenziali)
- file `.pkrvars.hcl` passato con `-var-file=`
- flag `-var nome=valore` sulla command line

| Variabile | Default | Descrizione |
|-----------|---------|-------------|
| `proxmox_url` | `$PROXMOX_URL` | URL API Proxmox |
| `proxmox_token_id` | `$PROXMOX_TOKEN_ID` | Token ID (es. `automation@pve!packer`) |
| `proxmox_token_secret` | `$PROXMOX_TOKEN_SECRET` | Secret UUID del token |
| `proxmox_node` | `pve` | Nome del nodo Proxmox |
| `vm_id_ubuntu_2204` | `9001` | VM ID per Ubuntu 22.04 |
| `vm_id_ubuntu_2404` | `9002` | VM ID per Ubuntu 24.04 |
| `vm_id_debian_13` | `9003` | VM ID per Debian 13 |
| `vm_id_rocky_9` | `9000` | VM ID per Rocky 9 |
| `template_storage_pool` | `local-lvm` | Storage per disco VM |
| `iso_storage_pool` | `local` | Storage per ISO installer |
| `network_bridge` | `vmbr0` | Bridge di rete Proxmox |
| `disk_size` | `32G` | Dimensione disco |
| `cores` | `4` | Core CPU della VM di build |
| `memory` | `8192` | RAM in MB della VM di build |
| `ssh_password` | `packer` | Password root per la connessione SSH di Packer |

Le variabili delle credenziali Proxmox usano `env("VAR_NAME")` come default: se la variabile d'ambiente è impostata, Packer la legge automaticamente senza bisogno di passarla esplicitamente.

---

### Template `.pkr.hcl` (es. `ubuntu-24.04.pkr.hcl`)

Ogni distribuzione ha il suo file `.pkr.hcl`. Definisce il `source` (come costruire la VM) e il `build` (cosa fare una volta avviata).

#### Blocco `packer`

```hcl
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
```

Specifica il plugin `packer-plugin-proxmox` per il builder `proxmox-iso` e `packer-plugin-ansible` per il provisioner Ansible. `packer init` li scarica automaticamente.

#### Connessione Proxmox

```hcl
proxmox_url              = var.proxmox_url
username                 = var.proxmox_token_id   # NON proxmox_token_id
token                    = var.proxmox_token_secret # NON proxmox_token_secret
insecure_skip_tls_verify = true
```

I nomi dei campi nel plugin sono `username` e `token` — non `proxmox_token_id` e `proxmox_token_secret` (che erano sbagliati nel template originale). `insecure_skip_tls_verify = true` è necessario perché Proxmox usa un certificato TLS self-signed di default.

#### Disco

```hcl
scsi_controller = "virtio-scsi-single"
disks {
  type         = "scsi"
  storage_pool = var.template_storage_pool
  format       = "raw"
  discard      = true
  io_thread    = true
}
```

- `virtio-scsi-single` è il controller più performante su KVM (con una coda I/O per disco)
- `format = "raw"` è obbligatorio per storage LVM; usare `qcow2` per NFS/ZFS/dir
- `discard = true` abilita il TRIM (supportato da Ubuntu con LVM)
- `io_thread = true` migliora le performance I/O

#### Cloud-init drive

```hcl
cloud_init              = true
cloud_init_storage_pool = var.template_storage_pool
```

Aggiunge un secondo disco di tipo `cloudinit` alla VM. Questo è il meccanismo che Terraform userà per iniettare IP statico, hostname e chiave SSH pubblica in ogni VM clonata dal template.

#### `boot_command`

```hcl
boot_wait = "5s"
boot_command = [
  "c<wait3>",
  "linux /casper/vmlinuz --- autoinstall net.ifnames=0 biosdevname=0 ds=nocloud-net\\;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/<enter><wait5>",
  "initrd /casper/initrd<enter><wait5>",
  "boot<enter>"
]
```

Packer invia questi tasti via VNC alla VM appena avviata:

1. **`boot_wait = "5s"`** — attesa iniziale per BIOS POST + comparsa menu GRUB
2. **`c`** — apre la GRUB command-line (più affidabile dell'editing del menu con `e`)
3. **`linux /casper/vmlinuz ...`** — carica il kernel con i parametri:
   - `autoinstall` — attiva la modalità installazione non interattiva di Ubuntu (Subiquity)
   - `ds=nocloud-net;s=http://...` — indica dove scaricare `user-data` e `meta-data`
   - `net.ifnames=0 biosdevname=0` — forza il nome dell'interfaccia di rete a `eth0` (altrimenti sarebbe `ens18` o simile, imprevedibile)
   - `{{ .HTTPIP }}` e `{{ .HTTPPort }}` sono template variable di Packer: vengono espanse con l'IP del bastion e la porta del server HTTP locale
4. **`initrd /casper/initrd`** — carica il ramdisk iniziale
5. **`boot`** — avvia il boot

**Requisito di rete:** il bastion deve essere raggiungibile dalle VM su `vmbr0`. Il server HTTP di Packer è in ascolto su `0.0.0.0` (porta casuale nel range 8000-9000).

---

### `http/ubuntu-user-data.tpl`

Template YAML per il sistema di autoinstall di Ubuntu (Subiquity). Non è un file statico: `build.sh` lo trasforma in `http/ubuntu-user-data` sostituendo i segnaposto `%%...%%` con i valori reali prima di avviare Packer.

Il file inizia obbligatoriamente con `#cloud-config` e contiene una chiave `autoinstall:`.

#### Sezioni principali

**`locale` e `keyboard`** — impostati su italiano per l'ambiente homelab.

**`network`**  
```yaml
network:
  network:
    version: 2
    ethernets:
      eth0:
        dhcp4: true
        dhcp-identifier: mac
```
Usa `eth0` perché il kernel viene avviato con `net.ifnames=0`. `dhcp-identifier: mac` garantisce che il server DHCP assegni sempre lo stesso IP basandosi sul MAC address.

**`identity`**  
```yaml
identity:
  hostname: ubuntu-base
  username: ubuntu
  password: "%%UBUNTU_PASSWORD_HASH%%"
```
Il campo `password` richiede un hash SHA-512 nel formato crypt(3). `build.sh` genera questo hash con `openssl passwd -6` e lo inserisce al posto di `%%UBUNTU_PASSWORD_HASH%%`.

**`packages`** — lista di pacchetti installati durante il setup. Include `qemu-guest-agent` (fondamentale per Proxmox), `cloud-init`, e gli strumenti base.

**`storage`**  
```yaml
storage:
  layout:
    name: lvm
```
Partizionamento LVM sull'intero disco. Semplicità massima per un template.

**`late-commands`** — comandi eseguiti nell'ambiente installato (in `chroot`) prima del reboot finale:

```yaml
late-commands:
  - "curtin in-target -- bash -c \"echo 'root:%%ROOT_PASSWORD%%' | chpasswd\""
  - "sed -i 's/^#\\?PermitRootLogin.*/PermitRootLogin yes/' /target/etc/ssh/sshd_config"
  - "sed -i 's/^#\\?PasswordAuthentication.*/PasswordAuthentication yes/' /target/etc/ssh/sshd_config"
  - "echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /target/etc/sudoers.d/ubuntu"
  - "chmod 0440 /target/etc/sudoers.d/ubuntu"
  - "curtin in-target -- systemctl enable qemu-guest-agent"
```

- `curtin in-target --` esegue il comando nel sistema installato (equivalente a `chroot /target`)
- Il root SSH viene abilitato perché Packer si connette come `root` con password
- `sudoers.d/ubuntu` permette all'utente `ubuntu` di usare sudo senza password (utile per Ansible post-clone)
- `qemu-guest-agent` viene abilitato al boot (necessario perché Proxmox e Terraform comunicano con la VM tramite questo agente)

---

### `http/meta-data`

File vuoto ma obbligatorio. Il protocollo `nocloud` (usato da `ds=nocloud-net`) prevede sempre due file: `user-data` e `meta-data`. Se `meta-data` non esiste, cloud-init/Subiquity va in errore. Il file vuoto è sufficiente.

---

### `scripts/install-tools.sh`

```bash
apt-get update -qq
apt-get upgrade -y -qq
apt-get clean && rm -rf /var/lib/apt/lists/*
```

Eseguito dal `shell` provisioner di Packer come primo step dopo che Ubuntu è installato e SSH è attivo. Il suo unico scopo è aggiornare tutti i pacchetti (inclusi eventuali aggiornamenti di sicurezza usciti dopo il rilascio dell'ISO) e pulire la cache apt per ridurre la dimensione del template.

I pacchetti applicativi sono già installati dall'autoinstall (`ubuntu-user-data.tpl`) per sfruttare il caching APT del processo di installazione.

---

### `ansible/playbooks/base.yml`

Playbook con doppio scopo, controllato dalla variabile `packer_build`:

| `packer_build` | Cosa viene eseguito |
|----------------|---------------------|
| `true` (Packer) | Cleanup template: qemu-guest-agent, cloud-init reset, SSH keys, machine-id, /tmp |
| `false` (default) | Installazione pacchetti comuni su VM post-clone |

#### Task di cleanup template (`when: packer_build`)

**`cloud-init clean --logs`**  
Reset completo dello stato cloud-init. Senza questo, quando Terraform clona il template e avvia la VM, cloud-init troverebbe le prove di una precedente esecuzione e non si rieseguirebbe — nessuna configurazione di rete/hostname/SSH key verrebbe applicata.

**Rimozione SSH host keys**  
```yaml
- /etc/ssh/ssh_host_rsa_key
- /etc/ssh/ssh_host_ecdsa_key
- /etc/ssh/ssh_host_ed25519_key
```
Le host key identificano univocamente un server SSH. Se tutte le VM clonate avessero le stesse host key, si avrebbero:
- Avvisi "REMOTE HOST IDENTIFICATION HAS CHANGED" ad ogni accesso
- Potenziali problemi di sicurezza (impossibile verificare l'identità del server)

`systemd-firstboot` o `ssh-keygen -A` (eseguiti da cloud-init al primo boot) le rigenera univoche.

**Truncate `machine-id`**  
`/etc/machine-id` è un identificatore univoco della macchina usato da systemd, D-Bus, e altri servizi. Se le VM clonate avessero lo stesso `machine-id`:
- I lease DHCP potrebbero essere condivisi (stesso IP assegnato a VM diverse)
- Alcuni servizi basati su `machine-id` potrebbero comportarsi in modo inatteso

Svuotandolo (non eliminandolo, perché deve esistere come file), `systemd-firstboot` lo rigenera univoco al primo avvio.

Il symlink `/var/lib/dbus/machine-id → /etc/machine-id` viene ricreato perché D-Bus legge da questo path alternativo.

---

## `build.sh`

```bash
UBUNTU_PASSWORD_HASH=$(openssl passwd -6 "${UBUNTU_PASSWORD}")

sed \
  -e "s|%%UBUNTU_PASSWORD_HASH%%|${UBUNTU_PASSWORD_HASH}|g" \
  -e "s|%%ROOT_PASSWORD%%|${ROOT_PASSWORD}|g" \
  http/ubuntu-user-data.tpl > http/ubuntu-user-data
```

**Perché non inserire l'hash direttamente nel template?**  
Il formato SHA-512 crypt(3) usa un salt casuale per ogni hash generato — non esiste un valore fisso. Inserire un hash hardcoded nel file committato sarebbe sia insicuro sia non riproducibile. `build.sh` genera l'hash fresco ad ogni build.

**Perché `openssl passwd -6` e non Python?**  
Il modulo `crypt` di Python 3 è stato deprecato in Python 3.13 e rimosso nelle versioni successive. `openssl passwd -6` è disponibile su qualsiasi sistema con OpenSSL e non ha questo problema di compatibilità.

**Controllo variabili obbligatorie:**  
```bash
: "${PROXMOX_URL:?Imposta la variabile PROXMOX_URL}"
```
La sintassi `:` con `?` fa fallire lo script con un messaggio chiaro se la variabile non è impostata, evitando che Packer parta con credenziali vuote.

---

## Autenticazione Proxmox

Il plugin Packer usa autenticazione via **API token** (non username/password):

```
Token ID:     automation@pve!packer
Token Secret: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

Il token deve essere creato con il playbook `ansible/playbooks/create_proxmox_user.yml` (vedi `proxmox-api-user.md`). I permessi richiesti per la build Packer sono almeno `PVEAdmin` sul nodo di destinazione.

Le variabili d'ambiente da esportare prima di `build.sh`:

```bash
export PROXMOX_URL="https://<IP_PROXMOX>:8006/api2/json"
export PROXMOX_TOKEN_ID="automation@pve!packer"
export PROXMOX_TOKEN_SECRET="<uuid-del-token>"
```

---

## Come funziona l'autoinstall Ubuntu

Ubuntu 22.04 usa **Subiquity** come installer. La modalità `autoinstall` consente un'installazione completamente non interattiva tramite un file di configurazione YAML.

Il flusso è:

1. Il kernel viene avviato con `autoinstall ds=nocloud-net;s=<URL>`
2. Subiquity scarica `<URL>/user-data` e `<URL>/meta-data`
3. L'installazione procede senza input utente
4. I `late-commands` vengono eseguiti nell'ambiente installato prima del reboot

La differenza con **cloud-init** (usato post-boot dalle VM clonate) è che autoinstall gira durante l'installer — Subiquity supporta un sottoinsieme della sintassi cloud-init per la configurazione del sistema.

---

## Perché il cleanup del template è importante

Un template Proxmox è fondamentalmente uno snapshot di disco. Tutte le VM create clonando questo template **partono con lo stesso stato**. Se non si pulisce:

| Elemento | Problema se non rimosso |
|----------|------------------------|
| `machine-id` | Tutte le VM ottengono lo stesso ID — conflitti DHCP, servizi systemd instabili |
| SSH host keys | Tutte le VM hanno la stessa identità SSH — warning SSH su ogni connessione |
| Cloud-init state | Cloud-init non si riesegue — nessuna configurazione di rete/hostname/SSH key da Terraform |

Il cleanup viene fatto nell'ultimo step prima che Packer converta la VM in template, garantendo che sia necessariamente l'ultima operazione.

---

## Utilizzo

### Prima build

```bash
# 1. Crea l'utente API Proxmox (solo la prima volta)
ansible-playbook ansible/playbooks/create_proxmox_user.yml --ask-vault-pass

# 2. Esporta le credenziali
export PROXMOX_URL="https://192.168.1.10:8006/api2/json"
export PROXMOX_TOKEN_ID="automation@pve!packer"
export PROXMOX_TOKEN_SECRET="<token-secret>"

# 3. Avvia la build
cd packer
./build.sh
```

### Opzioni avanzate

```bash
# Password personalizzate
UBUNTU_PASSWORD="mypass" ROOT_PASSWORD="mysecret" ./build.sh

# Build su nodo diverso
PACKER_ARGS="-var proxmox_node=pve2" ./build.sh

# Debug verboso
PACKER_ARGS="-debug" ./build.sh

# Solo validazione (non costruisce)
packer validate ubuntu-24.04.pkr.hcl
```

### Ricostruzione del template

Se il template esiste già, Packer fallisce (a meno di `-force`). Per ricostruirlo:

```bash
# Da Proxmox: cancella il template esistente (usa l'ID corretto)
qm destroy 9002   # Ubuntu 24.04

# Oppure usa -force per sovrascrivere
PACKER_ARGS="-force" ./build.sh ubuntu-24.04
```

---

## Troubleshooting

### La VM non risponde al `boot_command`

Sintomi: Packer resta in attesa all'avvio, non vede mai SSH.

Cause possibili:
- `boot_wait` troppo corto: il GRUB non ha ancora mostrato il menu quando Packer invia i tasti. Aumentare a `"10s"` o `"15s"`.
- VNC lag: il tasto `c` è stato inviato prima che GRUB fosse pronto. Aumentare `<wait3>` a `<wait5>`.

### Packer non riesce a scaricare `user-data`

Sintomi: l'installazione si blocca o va in errore cercando il datasource.

Cause possibili:
- Il bastion non è raggiungibile dalla rete delle VM Proxmox — verificare che il bastion abbia un IP su `vmbr0`.
- Firewall del bastion blocca le porte 8000-9000 — aprire il range con `ufw allow 8000:9000/tcp`.
- `http_bind_address` non corretto — lasciare `"0.0.0.0"`.

### SSH timeout dopo il reboot

Sintomi: Ubuntu si installa correttamente ma Packer va in timeout aspettando SSH.

Cause possibili:
- I `late-commands` non hanno abilitato correttamente root SSH — verificare `PermitRootLogin yes` nel template.
- `ssh_timeout` di 40 minuti esaurito su hardware lento — aumentare a `"60m"`.
- Il root password nell'`user-data` generato non corrisponde a `var.ssh_password` — verificare che `ROOT_PASSWORD` e `ssh_password` siano allineati.

### Errore checksum ISO

Sintomi: `Error downloading ISO: checksum mismatch`.

La URL di rilascio punta all'ultima point release ma il file `SHA256SUMS` potrebbe essere aggiornato. Soluzione: specificare la versione esatta in `build.sh` (modificando l'URL nel template `.pkr.hcl`) o scaricare l'ISO manualmente con `packer/download-isos.sh`.

### Il template clonato non riceve configurazione cloud-init

Sintomi: la VM avviata da Terraform ha IP DHCP invece dell'IP statico configurato.

Causa: cloud-init non si è rieseguito perché il suo stato non è stato pulito nel template.
Verifica: controllare che nel playbook `base.yml` il task `cloud-init clean --logs` venga eseguito con `packer_build=true`.
