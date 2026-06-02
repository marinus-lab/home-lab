# Terraform — Infrastruttura cluster K3S su Proxmox

## Indice

1. [Panoramica](#panoramica)
2. [Prerequisiti](#prerequisiti)
3. [Struttura dei file](#struttura-dei-file)
4. [Flusso di provisioning](#flusso-di-provisioning)
5. [File di configurazione](#file-di-configurazione)
   - [providers.tf](#providerstf)
   - [variables.tf](#variablestf)
   - [main.tf](#maintf)
6. [Provider bpg/proxmox](#provider-bpgproxmox)
7. [Modulo riutilizzabile proxmox-vm](#modulo-riutilizzabile-proxmox-vm)
8. [Inventory per K3S](#inventory-per-k3s)
9. [Integrazione con k3s/deploy.sh](#integrazione-con-k3sdeploysh)
10. [Utilizzo](#utilizzo)
11. [Troubleshooting](#troubleshooting)

---

## Panoramica

Questo modulo Terraform clona lo stesso template VM prodotto da Packer usato per il cluster K8s, creando **3 VM destinate a K3S**. Ogni VM riceve:

- IP statico via **cloud-init** (configurato dal drive cloud-init del template)
- Chiave SSH pubblica del bastion (per accesso `k3s/deploy.sh`)
- Stesse risorse hardware dei master K8s (4 CPU, 16 GB RAM)
- Tag Proxmox `k3s` per identificazione

Al termine del `terraform apply`, viene generato automaticamente il file `generated/k3s-inventory.ini` con gli IP delle VM, pronto per essere copiato in `k3s/inventory.ini` dal deploy script.

```
Packer template (es. VMID 9002 per Ubuntu 24.04)
        │
        ├── clone ──→ k3s-1  (VMID 44777, 192.168.1.160)
        ├── clone ──→ k3s-2  (VMID 44778, 192.168.1.161)
        └── clone ──→ k3s-3  (VMID 44779, 192.168.1.162)
```

Tutti e 3 i nodi sono **server** K3S: control plane + worker (nessun taint `NoSchedule`), con embedded etcd per HA. Il cluster K3S è completamente separato dal cluster K8s gestito da Kubespray.

---

## Prerequisiti

1. **Template Packer** — VMID corrispondente alla distribuzione scelta presente su Proxmox (es. 9002 per Ubuntu 24.04, creato da `packer/build.sh`)
2. **Token API Proxmox** — con ruolo `PVEAdmin` sul nodo (creato da `ansible/playbooks/create_proxmox_user.yml`)
3. **Chiave SSH** — `~/.ssh/id_rsa.pub` presente sul bastion (generata da `setup-bastion.sh`)
4. **Terraform** ≥ 1.5.0 installato sul bastion (installato da `setup-bastion.sh`)

---

## Struttura dei file

```
terraform-k3s/
├── providers.tf                       # Provider bpg/proxmox + hashicorp/local
├── variables.tf                       # Tutte le variabili di input
├── main.tf                            # Definizione cluster: nodi + inventory
├── terraform.tfvars*                  # Config topologia (generato da init-project.sh)
├── terraform.tfvars.example           # Esempio valori
├── .gitignore                         # Esclude tfstate, tfvars, .terraform/
├── templates/
│   └── k3s-inventory.tftpl            # Template per inventory K3S
└── generated/                         # File generati da Terraform (gitignored)
    └── k3s-inventory.ini              # Inventory K3S (creato dopo apply)
```

A differenza di `terraform/`, qui non c'è un modulo dedicato: il modulo `proxmox-vm` viene riusato direttamente da `../terraform/modules/proxmox-vm/`.

---

## Flusso di provisioning

```
terraform init
    └── Scarica provider bpg/proxmox (~0.66) e hashicorp/local

terraform plan
    ├── Calcola IP e VMID per ogni nodo (con cidrhost() e range())
    ├── Mostra le 3 VM che verranno create (k3s-1, k3s-2, k3s-3)
    └── Non crea nulla

terraform apply -parallelism=2
    ├── Per ogni nodo:
    │   ├── Clone full del template Packer (es. VMID 9002)
    │   ├── Resize disco se k3s_disk_size > disco template
    │   ├── Configura cloud-init (IP, gateway, DNS, SSH key)
    │   └── Avvia la VM → cloud-init applica la configurazione al boot
    └── Genera generated/k3s-inventory.ini

         ↓ (passo successivo)

cd ../k3s
./deploy.sh install   # Fase 1: single-node su k3s-1
./deploy.sh join      # Fase 2: aggiunge k3s-2 e k3s-3 per HA
```

---

## File di configurazione

### `providers.tf`

Identico al file corrispondente in `terraform/providers.tf`: provider `bpg/proxmox` con autenticazione via API token e `insecure = true` (certificato TLS self-signed).

```hcl
provider "proxmox" {
  endpoint  = var.proxmox_url
  api_token = "${var.proxmox_token_id}=${var.proxmox_token_secret}"
  insecure  = true
}
```

---

### `variables.tf`

Variabili principali e relative scelte di default:

| Variabile | Default | Motivazione |
|-----------|---------|-------------|
| `proxmox_node` | `"pve"` | Nome default del nodo Proxmox in un setup single-node |
| `template_vm_id` | `9000` | Template Ubuntu 22.04; va adattato alla distribuzione usata (9002 per 24.04) |
| `k3s_subnet` | `192.168.1.0/24` | Subnet tipica di rete domestica/homelab |
| `k3s_ip_start` | `160` | 3 IP consecutivi dopo lo spazio dei worker K8s (che finiscono a `.157`) |
| `k3s_vm_id_start` | `44777` | Range alto per non confliggere con le VM K8s (VMID 200-299) |
| `k3s_count` | `3` | 3 nodi server per HA con embedded etcd |
| `k3s_cpu_cores` | `4` | Stesso dei master K8s |
| `k3s_memory` | `16384` | 16 GB, stesso dei master K8s |
| `k3s_disk_size` | `0` | 0 = eredita la dimensione del disco dal template (default 32 GB) |

La variabile `k3s_disk_size = 0` viene gestita dal modulo `proxmox-vm`: quando `disk_size` è 0, il blocco `disk` non viene incluso nel resource, e la VM eredita il disco del template senza resize. Questo è voluto perché K3S è più leggero di Kubernetes completo e 32 GB sono sufficienti.

---

### `main.tf`

#### Generazione della topologia

```hcl
locals {
  k3s_nodes = {
    for i in range(var.k3s_count) :
    format("k3s-%d", i + 1) => {
      vm_id      = var.k3s_vm_id_start + i
      ip_address = cidrhost(var.k3s_subnet, var.k3s_ip_start + i)
    }
  }
}
```

Con `k3s_count = 3`, `k3s_vm_id_start = 44777`, `k3s_ip_start = 160`:

```
{
  "k3s-1" = { vm_id = 44777, ip_address = "192.168.1.160" }
  "k3s-2" = { vm_id = 44778, ip_address = "192.168.1.161" }
  "k3s-3" = { vm_id = 44779, ip_address = "192.168.1.162" }
}
```

#### `for_each` sul modulo

```hcl
module "k3s_node" {
  source   = "../terraform/modules/proxmox-vm"
  for_each = local.k3s_nodes

  name           = each.key
  ...
  tags           = ["k3s"]
}
```

Il modulo `proxmox-vm` è riusato da `terraform/modules/` (stesso percorso usato da `terraform/`). Con `for_each`, Terraform crea una istanza del modulo per ogni elemento della mappa. Le risorse nello state hanno nomi come:

```
module.k3s_node["k3s-1"].proxmox_virtual_environment_vm.this
module.k3s_node["k3s-2"].proxmox_virtual_environment_vm.this
```

#### Inventory K3S automatico

```hcl
resource "local_file" "k3s_inventory" {
  filename        = "${path.root}/generated/k3s-inventory.ini"
  content = templatefile("${path.root}/templates/k3s-inventory.tftpl", {
    nodes = { for k in keys(local.k3s_nodes) : k => module.k3s_node[k].ip_address }
  })
  depends_on = [module.k3s_node]
}
```

Il `depends_on` garantisce che l'inventory venga scritto **dopo** che tutti i moduli VM sono stati creati con successo. `deploy.sh` copia automaticamente questo file in `k3s/inventory.ini` se più recente.

---

## Provider `bpg/proxmox`

Il provider `bpg/proxmox` (`github.com/bpg/terraform-provider-proxmox`) è lo stesso usato da `terraform/` per il cluster K8s. Si veda [terraform-k8s-cluster.md#provider-bpgproxmox](terraform-k8s-cluster.md#provider-bpgproxmox) per i dettagli sulle motivazioni della scelta.

---

## Modulo riutilizzabile `proxmox-vm`

Il modulo `../terraform/modules/proxmox-vm` è condiviso tra i due cluster. Si veda [terraform-k8s-cluster.md#modulesproxmox-vm](terraform-k8s-cluster.md#modulesproxmox-vm) per la documentazione completa del modulo (clone, CPU, disco, cloud-init, lifecycle).

L'unica differenza per K3S è il tag: `tags = ["k3s"]` invece di `["kubernetes", "control-plane"]`.

---

## Inventory per K3S

Il template `templates/k3s-inventory.tftpl` genera un file INI molto più semplice rispetto a quello di Kubespray:

```ini
# Generato automaticamente da Terraform — non modificare manualmente.
# Copiare in: k3s/inventory.ini

[k3s_cluster]
k3s-1 ansible_host=192.168.1.160 ansible_user=ubuntu
k3s-2 ansible_host=192.168.1.161 ansible_user=ubuntu
k3s-3 ansible_host=192.168.1.162 ansible_user=ubuntu
```

Non ci sono gruppi separati per control plane e worker (tutti i nodi sono entrambi).

---

## Integrazione con `k3s/deploy.sh`

Il deploy script `k3s/deploy.sh` interagisce con Terraform in due modi:

1. **Copia l'inventory**: all'avvio, verifica se `terraform-k3s/generated/k3s-inventory.ini` è più recente di `k3s/inventory.ini` e in caso lo copia.
2. **Legge il primo host**: per la fase `install`, si connette al primo nodo dell'inventory (`k3s-1`) per installare K3S con `--cluster-init`.

Il flusso completo è quindi:

```bash
cd terraform-k3s && terraform apply -parallelism=2   # crea le VM
cd ../k3s && ./deploy.sh install                      # installa su k3s-1
kubectl --kubeconfig ~/.kube/k3s-config get nodes     # verifica
./deploy.sh join                                       # join k3s-2, k3s-3 per HA
```

---

## Utilizzo

### Prima installazione

```bash
cd /root/home-lab/terraform-k3s

# 1. I file di configurazione sono generati da init-project.sh
#    Verifica che siano presenti:
ls -la terraform.tfvars terraform.auto.tfvars

# 2. Inizializza Terraform (scarica provider)
terraform init

# 3. Verifica il piano
terraform plan

# 4. Applica (2 VM alla volta per non sovraccaricare lo storage)
terraform apply -parallelism=2

# 5. Verifica output
cat generated/k3s-inventory.ini
```

### Distruggere il cluster K3S

Prima di distruggere le VM, resettare K3S sui nodi:

```bash
cd /root/home-lab/k3s
./deploy.sh reset

cd /root/home-lab/terraform-k3s
terraform destroy
```

Proxmox spegne e cancella le VM. Il template (VMID 9000-9003) e le VM del cluster K8s non vengono toccati.

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

Causa: una VM con lo stesso VMID esiste già su Proxmox. I VMID K3S (44777+) sono volutamente alti per evitare conflitti con le VM K8s (200-299).

```bash
# Lista VM Proxmox
ssh root@<proxmox-ip> "qm list"

# Distruggi manualmente e riapplica
ssh root@<proxmox-ip> "qm stop 44777 && qm destroy 44777"
terraform apply -parallelism=2
```

### La VM si avvia ma cloud-init non configura la rete

Causa: cloud-init non si è rieseguito (stato non pulito nel template).

```bash
# Verifica nel template prima di clonare
ssh root@<proxmox-ip>
qm terminal 9002  # console seriale del template
# verificare che /var/lib/cloud/instances/ sia vuota
```

Se non è vuota, ricostruire il template con Packer (il playbook `base.yml` esegue `cloud-init clean`).

### SSH non funziona dopo il provisioning

Causa probabile: la chiave SSH non è stata iniettata correttamente.

```bash
# Verifica la chiave
cat ~/.ssh/id_rsa.pub

# Accedi alla VM dalla console Proxmox e verifica
qm terminal 44777
# cat /home/ubuntu/.ssh/authorized_keys
```

### `timeout while waiting for VM agent`

Causa: `qemu-guest-agent` non è in esecuzione nella VM. Verificare che il template sia stato costruito correttamente da Packer. Vedi [terraform-k8s-cluster.md#timeout-while-waiting-for-vm-agent](terraform-k8s-cluster.md#timeout-while-waiting-for-vm-agent).
