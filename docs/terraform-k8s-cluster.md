# Terraform — Infrastruttura cluster Kubernetes su Proxmox

## Indice

1. [Panoramica](#panoramica)
2. [Prerequisiti](#prerequisiti)
3. [Struttura dei file](#struttura-dei-file)
4. [Flusso di provisioning](#flusso-di-provisioning)
5. [File di configurazione](#file-di-configurazione)
   - [main.tf](#maintf)
   - [variables.tf](#variablestf)
   - [k8s-cluster.tf](#k8s-clustertf)
   - [outputs.tf](#outputstf)
   - [modules/proxmox-vm](#modulusproxmox-vm)
   - [templates/kubespray-inventory.tftpl](#templateskubespray-inventorytftpl)
6. [Provider bpg/proxmox](#provider-bpgproxmox)
7. [Come funziona cloud-init in questo contesto](#come-funziona-cloud-init-in-questo-contesto)
8. [Scalabilità del cluster](#scalabilità-del-cluster)
9. [Utilizzo](#utilizzo)
10. [Troubleshooting](#troubleshooting)

---

## Panoramica

Questo modulo Terraform clona il template VM prodotto da Packer per creare i nodi del cluster Kubernetes. Ogni VM riceve:

- IP statico via **cloud-init** (configurato dal drive cloud-init del template)
- Chiave SSH pubblica del bastion (per accesso Ansible/Kubespray)
- Risorse hardware parametrizzate (CPU, RAM, disco)
- Tag Proxmox per identificazione (`kubernetes`, `control-plane` / `worker`)

Al termine del `terraform apply`, viene generato automaticamente il file `generated/kubespray-inventory.ini` con gli IP reali delle VM, pronto per essere usato da Kubespray.

```
Packer template (es. VMID 9002 per Ubuntu 24.04)
        │
        ├── clone ──→ k8s-master-1 (VMID 201, 192.168.1.210)
        ├── clone ──→ k8s-master-2 (VMID 202, 192.168.1.211)  ← solo se control_plane_count=3
        ├── clone ──→ k8s-master-3 (VMID 203, 192.168.1.212)  ← solo se control_plane_count=3
        ├── clone ──→ k8s-worker-1 (VMID 211, 192.168.1.220)
        ├── clone ──→ k8s-worker-2 (VMID 212, 192.168.1.221)
        └── clone ──→ k8s-worker-3 (VMID 213, 192.168.1.222)
```

---

## Prerequisiti

1. **Template Packer** — VMID corrispondente alla distribuzione scelta presente su Proxmox (es. 9002 per Ubuntu 24.04, creato da `packer/build.sh`)
2. **Token API Proxmox** — con ruolo `PVEAdmin` sul nodo (creato da `create_proxmox_user.yml`)
3. **Chiave SSH** — `~/.ssh/id_rsa.pub` presente sul bastion (generata da `setup-bastion.sh`)
4. **Terraform** ≥ 1.5.0 installato sul bastion (installato da `setup-bastion.sh`)

---

## Struttura dei file

```
terraform/
├── main.tf                           # Provider bpg/proxmox + locals
├── variables.tf                      # Tutte le variabili di input
├── k8s-cluster.tf                    # Definizione cluster: master + worker + inventory
├── outputs.tf                        # Output: IP, comandi SSH, path inventory
├── terraform.tfvars.example          # Esempio valori (da copiare in terraform.tfvars)
├── .gitignore                        # Esclude tfstate, tfvars, .terraform/ da git
├── templates/
│   └── kubespray-inventory.tftpl     # Template HCL per generare hosts.ini
├── generated/                        # File generati da Terraform (gitignored)
│   └── kubespray-inventory.ini       # Inventory Kubespray (creato dopo apply)
└── modules/
    └── proxmox-vm/
        ├── main.tf                   # Resource proxmox_virtual_environment_vm
        ├── variables.tf              # Variabili del modulo
        └── outputs.tf                # Output: ip_address, name, vm_id
```

---

## Flusso di provisioning

```
terraform init
    └── Scarica provider bpg/proxmox (~0.66) e hashicorp/local

terraform plan
    ├── Calcola IP e VMID per ogni nodo (con cidrhost() e range())
    ├── Mostra le VM che verranno create
    └── Non crea nulla

terraform apply
    ├── Per ogni nodo master:
    │   ├── Clone full del template Packer (es. VMID 9002)
    │   ├── Resize disco se disk_size > disco template
    │   ├── Configura cloud-init (IP, gateway, DNS, SSH key)
    │   └── Avvia la VM → cloud-init applica la configurazione al boot
    ├── Per ogni nodo worker:
    │   └── (stesso flusso del master)
    └── Genera generated/kubespray-inventory.ini

         ↓ (passo successivo)

cd ../kubespray
./deploy.sh  # copia inventory automaticamente + esegue il playbook
```

---

## File di configurazione

### `main.tf`

#### Provider `bpg/proxmox`

```hcl
provider "proxmox" {
  endpoint  = var.proxmox_url
  api_token = "${var.proxmox_token_id}=${var.proxmox_token_secret}"
  insecure  = true
}
```

Il campo `api_token` richiede il formato `"user@realm!tokenname=<secret-uuid>"`. Per esempio:
```
automation@pve!terraform=a1b2c3d4-e5f6-7890-abcd-ef1234567890
```

`insecure = true` è necessario perché Proxmox usa un certificato TLS self-signed. In produzione si può caricare il certificato CA con `tls_insecure = false` + `tls_ca_file`.

#### Locals

```hcl
locals {
  ssh_public_key = trimspace(file(var.ssh_public_key_path))
  cidr_prefix    = split("/", var.k8s_subnet)[1]
}
```

- `trimspace(file(...))` — rimuove newline finali che potrebbero invalidare la chiave SSH in cloud-init
- `split("/", "192.168.1.0/24")[1]` → `"24"` — il prefisso CIDR viene estratto dalla subnet per passarlo al modulo

---

### `variables.tf`

Variabili principali e relative scelte di default:

| Variabile | Default | Motivazione |
|-----------|---------|-------------|
| `proxmox_node` | `"pve"` | Nome default del nodo Proxmox in un setup single-node |
| `template_vm_id` | `9002` | Allineato con il VMID Ubuntu 24.04 di Packer; 9000=Rocky, 9001=22.04, 9003=Debian |
| `k8s_subnet` | `192.168.1.0/24` | Subnet tipica di rete domestica/homelab |
| `master_ip_start` | `210` | IP alti per non conflitti con DHCP (che tipicamente assegna 100-200) |
| `worker_ip_start` | `220` | 10 IP di gap dai master per espansione futura |
| `master_vm_id_start` | `201` | Range 201-210 per master (max 10 nodi) |
| `worker_vm_id_start` | `211` | Range 211+ per worker |
| `control_plane_count` | `3` | Setup HA (3 master) per homelab; `1` per minimal |

La variabile `control_plane_count` include una validation:
```hcl
validation {
  condition     = contains([1, 3], var.control_plane_count)
  error_message = "Il control plane deve essere composto da 1 nodo (minimal) o 3 nodi (HA)."
}
```
Kubernetes con etcd embedded funziona correttamente solo con un numero **dispari** di control plane (1 o 3 per homelab). Con 2 nodi il cluster perde il quorum se uno va down.

---

### `k8s-cluster.tf`

#### Generazione dinamica della topologia

```hcl
locals {
  control_plane_nodes = {
    for i in range(var.control_plane_count) :
    format("k8s-master-%d", i + 1) => {
      vm_id      = var.master_vm_id_start + i
      ip_address = cidrhost(var.k8s_subnet, var.master_ip_start + i)
    }
  }
}
```

La funzione `cidrhost(subnet, host_number)` calcola l'IP a partire dall'indice nella subnet:
```
cidrhost("192.168.1.0/24", 210) = "192.168.1.210"
cidrhost("192.168.1.0/24", 211) = "192.168.1.211"
```

Il risultato con `control_plane_count = 3` e `master_ip_start = 210`:
```
{
  "k8s-master-1" = { vm_id = 201, ip_address = "192.168.1.210" }
  "k8s-master-2" = { vm_id = 202, ip_address = "192.168.1.211" }
  "k8s-master-3" = { vm_id = 203, ip_address = "192.168.1.212" }
}
```

#### `for_each` sui moduli

```hcl
module "k8s_master" {
  source   = "./modules/proxmox-vm"
  for_each = local.control_plane_nodes
  ...
}
```

Con `for_each`, Terraform crea una istanza del modulo per ogni elemento della mappa. Le risorse nello state hanno nomi come:
```
module.k8s_master["k8s-master-1"].proxmox_virtual_environment_vm.this
module.k8s_master["k8s-master-2"].proxmox_virtual_environment_vm.this
```

Questo permette di aggiungere/rimuovere nodi senza distruggere quelli esistenti (a differenza di `count`).

#### Inventory Kubespray automatico

```hcl
resource "local_file" "kubespray_inventory" {
  filename = "${path.root}/generated/kubespray-inventory.ini"
  content  = templatefile("${path.root}/templates/kubespray-inventory.tftpl", {
    control_plane = { for k in keys(local.control_plane_nodes) : k => module.k8s_master[k].ip_address }
    workers       = { for k in keys(local.worker_nodes) : k => module.k8s_worker[k].ip_address }
  })
  depends_on = [module.k8s_master, module.k8s_worker]
}
```

Il `depends_on` garantisce che l'inventory venga scritto **dopo** che tutti i moduli VM sono stati creati con successo. Gli IP passati al template provengono dall'output del modulo (non dalla variabile), quindi sono gli IP effettivamente configurati.

---

### `outputs.tf`

Output disponibili dopo `terraform apply`:

```bash
terraform output control_plane_ips
# { "k8s-master-1" = "192.168.1.210" }

terraform output all_nodes
# {
#   "k8s-master-1" = "192.168.1.210"
#   "k8s-worker-1" = "192.168.1.220"
#   "k8s-worker-2" = "192.168.1.221"
# }

terraform output ssh_command_examples
# {
#   "k8s-master-1" = "ssh ubuntu@192.168.1.210"
#   "k8s-worker-1" = "ssh ubuntu@192.168.1.220"
# }
```

---

### `modules/proxmox-vm`

#### Resource `proxmox_virtual_environment_vm`

**Clone**
```hcl
clone {
  vm_id   = var.template_vm_id
  full    = true
  retries = 3
}
```
`full = true` è obbligatorio perché il template usa dischi in formato `raw` su LVM (i linked clone richiedono `qcow2`). `retries = 3` gestisce eventuali race condition dell'API Proxmox su sistemi sotto carico.

**CPU**
```hcl
cpu {
  cores = var.cores
  type  = "x86-64-v2-AES"
}
```
`x86-64-v2-AES` è il tipo CPU ottimale per Ubuntu 22.04+: supporta le istruzioni AES-NI (accelerazione crittografia), richieste da Kubernetes per le comunicazioni TLS tra i componenti.

**Disco**
```hcl
disk {
  interface   = "scsi0"
  size        = var.disk_size
  discard     = "on"
  iothread    = true
  file_format = "raw"
}
```
- `interface = "scsi0"` — deve corrispondere al disco creato da Packer nel template
- `size` — se maggiore del disco del template (default 32G), il provider esegue un resize automatico
- `discard = "on"` + `iothread = true` — migliorano le performance I/O su storage LVM

**Cloud-init (initialization)**
```hcl
initialization {
  datastore_id = var.storage_pool
  ip_config {
    ipv4 {
      address = "${var.ip_address}/${var.cidr_prefix}"
      gateway = var.gateway
    }
  }
  user_account {
    username = "ubuntu"
    keys     = [var.ssh_public_key]
  }
}
```
Il blocco `initialization` scrive i dati nel drive cloud-init che Packer ha aggiunto al template. Al primo boot, cloud-init legge il drive e:
1. Configura l'interfaccia di rete con l'IP statico
2. Aggiunge la chiave SSH pubblica in `/home/ubuntu/.ssh/authorized_keys`
3. Imposta l'hostname uguale al nome della VM

**lifecycle**
```hcl
lifecycle {
  ignore_changes = [
    initialization[0].user_account[0].keys,
  ]
}
```
Senza questo, ogni `terraform plan` dopo il primo apply rileva una "modifica" alle SSH key (perché il provider le legge in un formato diverso da come le ha scritte). `ignore_changes` fa sì che le chiavi vengano iniettate una sola volta al provisioning iniziale.

---

### `templates/kubespray-inventory.tftpl`

Template HCL (sintassi Terraform `templatefile`) che genera un file INI compatibile con Ansible/Kubespray:

```ini
[kube_control_plane]
k8s-master-1 ansible_host=192.168.1.210 ansible_user=ubuntu

[kube_node]
k8s-worker-1 ansible_host=192.168.1.220 ansible_user=ubuntu
k8s-worker-2 ansible_host=192.168.1.221 ansible_user=ubuntu

[etcd:children]
kube_control_plane

[k8s_cluster:children]
kube_control_plane
kube_node

[calico_rr]
```

La sezione `[calico_rr]` (Route Reflectors per Calico BGP) è vuota ma necessaria affinché Kubespray non riporti errori sull'inventory.

---

## Provider `bpg/proxmox`

Il provider `bpg/proxmox` (`github.com/bpg/terraform-provider-proxmox`) è la scelta preferita rispetto al più vecchio `Telmate/proxmox` per questi motivi:

| Caratteristica | `bpg/proxmox` | `Telmate/proxmox` |
|----------------|---------------|-------------------|
| Supporto cloud-init | Nativo e completo | Parziale |
| Syntax HCL2 | Nativa | Parziale |
| Manutenzione attiva | Sì | Discontinua |
| API Proxmox 8.x | Supportata | Problemi noti |
| Tags VM | Supportato | Non supportato |

La versione `~> 0.66` usa il constraint di minor version: aggiornamenti patch e minor sono automatici, i breaking changes di major sono bloccati.

---

## Come funziona cloud-init in questo contesto

Il flusso cloud-init per le VM clonate è:

```
terraform apply
    │
    ├── Clone VM dal template
    │   └── Il template include già un drive cloud-init (aggiunto da Packer)
    │
    ├── Terraform scrive i dati nel drive cloud-init:
    │   ├── user-data  → chiave SSH, username
    │   ├── network-config → IP statico, gateway, DNS
    │   └── meta-data  → instance-id, hostname
    │
    └── VM si avvia → cloud-init legge il drive (datasource NoCloud)
        ├── Configura eth0 con IP statico
        ├── Aggiunge SSH key in /home/ubuntu/.ssh/authorized_keys
        ├── Imposta hostname = nome VM
        └── cloud-init marca se stesso come "eseguito" per questo instance-id
```

Questo meccanismo funziona perché Packer ha eseguito `cloud-init clean` nel template: ogni VM clonata vede un "primo boot" e riesegue cloud-init con i dati specifici iniettati da Terraform.

---

## Scalabilità del cluster

### Aggiungere worker

Incrementare `worker_count` e lanciare `terraform apply`. Terraform crea solo i nuovi nodi senza toccare quelli esistenti (grazie al `for_each`).

```hcl
# terraform.tfvars
worker_count = 4  # era 2
```

```bash
terraform apply  # crea solo k8s-worker-3 e k8s-worker-4
```

### Passare da minimal a HA (1 → 3 master)

```hcl
control_plane_count = 3
```

```bash
terraform apply  # crea k8s-master-2 e k8s-master-3
```

Dopo il `terraform apply`, Kubespray va rieseguito per aggiungere i nuovi master all'etcd cluster e al control plane.

### Rimuovere un nodo

Per rimuovere in modo pulito un nodo worker dal cluster Kubernetes **prima** di rimuoverlo con Terraform:

```bash
kubectl drain k8s-worker-2 --ignore-daemonsets --delete-emptydir-data
kubectl delete node k8s-worker-2
```

Poi ridurre `worker_count` e applicare:
```bash
terraform apply  # distrugge la VM k8s-worker-2 su Proxmox
```

---

## Utilizzo

### Prima installazione

```bash
cd /root/home-lab/terraform

# 1. Copia e compila il file variabili
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars

# 2. Inizializza Terraform (scarica provider)
terraform init

# 3. Verifica il piano
terraform plan

# 4. Applica
terraform apply

# 5. Verifica output
terraform output all_nodes
terraform output kubespray_inventory_path
```

### Inventario Kubespray

```bash
# L'inventory viene copiato automaticamente da deploy.sh
# Verifica manuale:
cat generated/kubespray-inventory.ini
```

### Distruggere il cluster

```bash
terraform destroy
```

Proxmox spegne e cancella le VM. Il template (VMID 9000) non viene toccato.

---

## Troubleshooting

### `Error: failed to clone VM`

Causa: il template VMID non esiste su Proxmox.

```bash
# Verifica che il template esista (usa l'ID corretto)
ssh root@<proxmox-ip> "qm list | grep -E '9[0-9]{3}'"

# Se non esiste, ricostruire con Packer
cd /root/home-lab/packer && ./build.sh
```

### `Error: VM ID already exists`

Causa: una VM con lo stesso VMID esiste già su Proxmox (da una build precedente o manuale).

```bash
# Lista VM Proxmox
ssh root@<proxmox-ip> "qm list"

# Opzione A: importa nel tfstate esistente
terraform import 'module.k8s_master["k8s-master-1"].proxmox_virtual_environment_vm.this' <node>/qemu/<vmid>

# Opzione B: distruggi manualmente e riapplica
ssh root@<proxmox-ip> "qm stop 201 && qm destroy 201"
terraform apply
```

### La VM si avvia ma cloud-init non configura la rete

Causa: cloud-init non si è rieseguito (stato non pulito nel template).

Verifica nel template prima di clonare:
```bash
ssh root@<proxmox-ip>
qm terminal 9000  # console seriale del template
# verificare che /var/lib/cloud/instances/ sia vuota
```

Se non è vuota, ricostruire il template con Packer (il playbook `base.yml` esegue `cloud-init clean`).

### SSH non funziona dopo il provisioning

Causa probabile: la chiave SSH non è stata iniettata correttamente.

```bash
# Verifica la chiave nel file tfvars
cat ~/.ssh/id_rsa.pub

# Verifica dall'output Terraform
terraform output ssh_command_examples

# Accedi alla VM dalla console Proxmox (senza SSH) e verifica
qm terminal <vmid>
# cat /home/ubuntu/.ssh/authorized_keys
```

### `timeout while waiting for VM agent`

Causa: `qemu-guest-agent` non è in esecuzione nella VM.

Verificare che il template sia stato costruito correttamente da Packer (il playbook `base.yml` abilita `qemu-guest-agent`). In alternativa, aumentare il timeout nel provider:

```hcl
provider "proxmox" {
  ...
  # timeout globale per le operazioni VM
}
```

O controllare lo stato dell'agente nella console Proxmox: `qm agent <vmid> ping`.
