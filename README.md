# Homelab Kubernetes + K3S su Proxmox

Infrastructure-as-Code per cluster Kubernetes su Proxmox VE:
- **K8s** (Kubespray): cluster HA con 3 master + 3 worker, Calico, kube-vip, MetalLB
- **K3S** (leggero): cluster HA con 3 server, embedded etcd (opzionale, separato)

## Getting Started from scratch (fresh Proxmox)

Partendo da un'installazione vergine di Proxmox, questa guida crea il container LXC che fungerà da bastion per tutto il progetto.

```bash
# 1. Accedi al nodo Proxmox via SSH o console, poi crea un container
#    Ubuntu 24.04 LXC con gli script helper della community:
bash -c "$(wget -qLO - https://github.com/community-scripts/ProxmoxVE/raw/main/ct/ubuntu.sh)"

# 2. Entra nel container e installa git
pct enter <CT_ID>
apt update && apt install -y git

# 3. Clona il repository
git clone https://github.com/marinus-lab/home-lab.git
cd home-lab

# 4. Installa tutto il tooling (Packer, Terraform, Ansible, kubectl, GitHub Copilot CLI, Gemini CLI, ...)
bash setup-bastion.sh

# 5. Configura credenziali Proxmox, rete K8s e vault cifrato
bash init-project.sh

# 6. Ora sei pronto per il Quick start qui sotto
```

## Stack

| Tool | Versione | Ruolo |
|------|----------|-------|
| Proxmox VE | 7.x / 8.x | Hypervisor |
| Packer | ≥ 1.9 | Build template VM (Ubuntu 22.04/24.04, Debian 13, Rocky 9) |
| Terraform | ≥ 1.5 | Provisioning VM dal template (K8s + K3S) |
| Kubespray | v2.31.0 | Installazione Kubernetes |
| K3S | latest | Kubernetes leggero (cluster separato) |
| Kubernetes | v1.35.4 | Container orchestration (via Kubespray, cluster K8s) |
| K3S | latest | Container orchestration (via install script, cluster K3S separato) |
| Calico | bundled | CNI (overlay IPIP) |
| containerd | bundled | Container runtime |
| kube-vip | bundled | HA control plane (VIP 192.168.0.80 via ARP) |
| MetalLB | latest | Load balancer bare-metal (Layer 2) |
| cert-manager | latest | Certificati TLS automatici |
| ingress-nginx | latest | Ingress controller |
| Kubernetes Dashboard | latest | UI monitoraggio cluster |

## Prerequisiti di rete

La fase **Packer** (build template VM) richiede:

- **Server DHCP attivo** sulla rete Proxmox — la VM di build riceve un IP temporaneo via DHCP durante l'installazione automatica da ISO. Dopo il clone con Terraform, i nodi K8s usano invece IP statici assegnati via cloud-init.
- **Bastion raggiungibile dalla rete VM** — Packer avvia un server HTTP temporaneo (porta 8613+) dal quale l'installer scarica la configurazione kickstart/autoinstall. Il bastion e la VM devono essere sulla stessa rete o comunque instradabili.

## Architettura

```
Bastion ──API──▶ Proxmox VE
                    │
                    ├─ Template VMID 9000-9003  (Packer)
                    │       │
                    │       ├─ clone ──▶ k8s-master-1  192.168.0.150  (16GB RAM, 4 CPU)
                    │       ├─ clone ──▶ k8s-master-2  192.168.0.151  (16GB RAM, 4 CPU)
                    │       ├─ clone ──▶ k8s-master-3  192.168.0.152  (16GB RAM, 4 CPU)
                    │       ├─ clone ──▶ k8s-worker-1  192.168.0.155  (16GB RAM, 4 CPU)
                    │       ├─ clone ──▶ k8s-worker-2  192.168.0.156  (16GB RAM, 4 CPU)
                    │       ├─ clone ──▶ k8s-worker-3  192.168.0.157  (16GB RAM, 4 CPU)
                    │       │
                    │       └─ clone ──▶ k3s-1  192.168.0.160  (16GB RAM, 4 CPU)  ◄── K3S
                    │         └─ clone ──▶ k3s-2  192.168.0.161  (16GB RAM, 4 CPU)  ◄──
                    │           └─ clone ──▶ k3s-3  192.168.0.162  (16GB RAM, 4 CPU)  ◄──
                    │
Bastion ──SSH──▶ 6 nodi K8s  (Kubespray)
Bastion ──SSH──▶ 3 nodi K3S  (k3s/deploy.sh)
                    │
                    ├─ kube-vip: 192.168.0.80 (VIP control plane via ARP)
                    ├─ MetalLB: 192.168.0.120-192.168.0.135 (load balancing servizi)
                    └─ Registry locale immagini su ogni nodo
```

**Topologia cluster K8s:**
- **3 nodi Control Plane** (HA etcd): k8s-master-1/2/3
- **3 nodi Worker**: k8s-worker-1/2/3
- **Totale K8s**: 6 VM, ognuna con 16GB RAM + 4 CPU

**Topologia cluster K3S (opzionale):**
- **3 nodi Server** (HA embedded etcd): k3s-1/2/3 (control plane + worker, nessun taint)
- **Totale K3S**: 3 VM, ognuna con 16GB RAM + 4 CPU

## Struttura del repository

```
home-lab/
├── init-project.sh                        # Setup iniziale: credenziali, utente API, token, storage
├── verify-init.sh                         # Verifica post-init: file, vault, token, storage, dipendenze
├── verify-cluster.sh                      # Health check cluster K8s: nodi, componenti, addon
├── demo-cluster.sh                        # Demo: Tetris, Hello K8s, Podinfo, registry, MetalLB
├── setup-bastion.sh                       # Installa tooling sul bastion (tmux dashboard)
├── create_proxmox_user.yml                # Playbook Ansible alternativo per utente Proxmox
├── requirements.yml                       # Dipendenze Ansible Galaxy (community.general)
│
├── packer/                                # Build template VM (Ubuntu 22.04, Ubuntu 24.04, Debian 13, Rocky 9)
│   ├── variables.pkr.hcl                  # Variabili condivise (Proxmox, VM, storage, SSH)
│   ├── packer.pkrvars.hcl*                # Credenziali Packer (*in .gitignore)
│   ├── packer.pkrvars.hcl.example         # Template credenziali
│   ├── ubuntu-22.04.pkr.hcl               # Source + build Ubuntu 22.04 LTS
│   ├── ubuntu-24.04.pkr.hcl               # Source + build Ubuntu 24.04 LTS
│   ├── debian-13.pkr.hcl                  # Source + build Debian 13 Trixie
│   ├── rocky-9.pkr.hcl                    # Source + build Rocky Linux 9
│   ├── build.sh                           # Menu interattivo per buildare le 4 distro
│   ├── download-isos.sh                   # Scarica/carica ISO su Proxmox via API
│   ├── http/
│   │   ├── ubuntu-user-data.tpl           # Template cloud-config autoinstall Ubuntu
│   │   ├── debian-preseed.cfg.tpl         # Template preseed Debian 13
│   │   ├── rocky-ks.cfg.tpl               # Template kickstart Rocky 9
│   │   └── meta-data                      # cloud-init metadata
│   └── scripts/
│       └── install-tools.sh               # Provisioner: apt update/upgrade + cleanup
│
├── terraform/                             # Provisioning VM cluster K8s (Kubespray)
│   ├── main.tf                            # Provider proxmox (bpg), locals (SSH, CIDR)
│   ├── variables.tf                       # Variabili: Proxmox, rete, storage, master/worker
│   ├── k8s-cluster.tf                     # Core: topologia dinamica, moduli VM, inventory
│   ├── outputs.tf                         # IP nodi, inventory path, comandi SSH
│   ├── terraform.tfvars                   # Config cluster (tracciato: topologia, risorse)
│   ├── terraform.tfvars.example           # Template completo con tutti i parametri
│   ├── terraform.auto.tfvars*             # Credenziali + rete (*in .gitignore, da init-project.sh)
│   ├── terraform.auto.tfvars.example      # Template credenziali
│   ├── create-vm.sh                       # Script interattivo: crea una VM singola di test
│   ├── single-vm/                         # Root module Terraform per VM singola
│   │   ├── main.tf                        # Provider + modulo proxmox-vm
│   │   ├── variables.tf                   # Parametri VM
│   │   └── outputs.tf                     # IP, nome, VM ID
│   ├── modules/proxmox-vm/                # Modulo riutilizzabile per singola VM
│   │   ├── main.tf                        # Clone, cloud-init, disco, rete, QEMU agent
│   │   ├── variables.tf                   # 18 variabili (nome, risorse, rete, SSH)
│   │   └── outputs.tf                     # IP, nome, VM ID
│   └── templates/
│       └── kubespray-inventory.tftpl      # Template Ansible inventory per Kubespray
│
├── terraform-k3s/                         # Provisioning VM cluster K3S
│   ├── providers.tf                       # Provider Proxmox (stesso modulo proxmox-vm)
│   ├── variables.tf                       # Variabili: ID VM, IP, risorse, rete
│   ├── main.tf                            # 3 VM k3s-{1..3} + inventory generato
│   ├── terraform.tfvars*                  # Topologia (generato da init-project.sh)
│   ├── terraform.tfvars.example           # Template topologia
│   ├── terraform.auto.tfvars*             # Credenziali + rete (*in .gitignore)
│   └── templates/
│       └── k3s-inventory.tftpl            # Template inventory per k3s/deploy.sh
│
├── k3s/                                   # Deploy K3S
│   ├── deploy.sh                          # Comandi: install | join | reset
│   └── inventory.ini                      # Inventory (generato da terraform-k3s)
│
├── kubespray/                             # Deploy Kubernetes
│   ├── ansible.cfg                        # Config Ansible (ruoli, SSH, parallelismo)
│   ├── deploy.sh                          # Comandi: install | upgrade | remove-node | reset
│   └── inventory/homelab/
│       ├── hosts.ini                      # Inventory (generato da Terraform)
│       └── group_vars/
│           ├── all/
│           │   ├── all.yml                # Cluster name, K8s v1.30.4, DNS, NTP, SSH
│           │   └── containerd.yml         # Runtime containerd
│           └── k8s_cluster/
│               ├── k8s-cluster.yml        # CIDR, kube-proxy, DNS, NTP, registry, certificati
│               ├── k8s-net-plugin.yml     # Calico IPIP, MTU, bird backend
│               └── addons.yml             # Helm, Metrics, Dashboard, Ingress, cert-manager, MetalLB, kube-vip
│
├── ansible/playbooks/                     # Playbook per preparazione template VM
│   ├── base.yml                           # Locale IT, qemu-agent, cloud-init reset, SSH keys
│   └── proxmox_image_import.yml           # Import alternativo immagini qcow2
│
├── group_vars/
│   └── all.yml                            # Credenziali Proxmox cifrate con Ansible Vault
│
└── docs/                                  # Documentazione dettagliata
    ├── init-project.md                    # Setup iniziale, credenziali, Vault
    ├── cluster-configuration.md           # Topologia, MetalLB, Dashboard
    ├── packer-multiple-distributions.md   # Ubuntu 22.04/24.04, Rocky 9
    ├── packer-ubuntu-base.md              # Dettaglio build Packer Ubuntu
    ├── terraform-k8s-cluster.md           # Provider, moduli, cloud-init, scalabilità
    ├── kubespray-deploy.md                # group_vars, Calico, gestione nodi
    ├── proxmox-api-user.md                # Utente API, Vault, permessi, token
    └── end-to-end.md                      # Guida completa end-to-end
```

**Legenda file:**
- ✅ Tracciati in git: `terraform.tfvars`, `group_vars/all.yml` (Vault cifrato), documentazione, `.example`
- ❌ Ignorati da git (`*.auto.tfvars`, `packer.pkrvars.hcl`): contengono token e credenziali
- 🔐 File `.example`: template da copiare e compilare per setup manuale

## Quick start

```bash
# 1. Bastion — installa tutto il tooling (inclusi GitHub Copilot CLI e Gemini CLI)
bash setup-bastion.sh

# 2. Inizializzazione — crea credenziali Proxmox e configurazione rete
bash init-project.sh
# Domande: IP Proxmox, password root, nome automation user, password API, subnet K8s, IP master/worker, password Vault

# 3. Verifica
bash verify-init.sh
# Controlla: file di config, vault, connessione API Proxmox, token

# 4. (Opzionale) Personalizza topologia cluster
# Nota: Subnet K8s e IP master/worker sono già configurati da init-project.sh
vim terraform/terraform.tfvars  # modifica control_plane_count, worker_count, risorse (se desiderato)

# 5. (Opzionale) Scarica ISO su Proxmox — necessario per Rocky 9, consigliato per Ubuntu
cd packer && ./download-isos.sh    # Menu interattivo (usa aria2c + API Proxmox)
# Oppure: ./download-isos.sh rocky-9

# 6. Packer — build template VM
# Supporta: Ubuntu 22.04 LTS, Ubuntu 24.04 LTS, Debian 13, Rocky Linux 9
./build.sh    # Menu interattivo per scegliere distribuzione
# Oppure:
# ./build.sh ubuntu-22.04
# ./build.sh ubuntu-24.04
# ./build.sh debian-13
# ./build.sh rocky-9

# 7. (Opzionale) Test singola VM prima del cluster
# Crea una VM singola per verificare che template e rete funzionino
cd ../terraform && bash create-vm.sh
# Dopo il test: cd single-vm && terraform destroy

# 8. Terraform — crea il cluster K8s (6 VM) — 2 VM alla volta per non sovraccaricare lo storage
terraform init
terraform apply -parallelism=2

# 9. Kubespray — installa Kubernetes
cd ../kubespray && ./deploy.sh

# 10. Verifica cluster K8s
bash ../verify-cluster.sh
# Oppure manualmente:
# kubectl get nodes
# kubectl get pods -A
# kubectl get svc -A  # verifica MetalLB

# 11. (Opzionale) Terraform — crea il cluster K3S (3 VM)
cd ../terraform-k3s && terraform init && terraform apply -parallelism=2

# 12. (Opzionale) K3S — deploy (due fasi)
cd ../k3s && ./deploy.sh install     # Fase 1: single-node su k3s-1
kubectl --kubeconfig ~/.kube/k3s-config get nodes
./deploy.sh join                     # Fase 2: join k3s-2, k3s-3 per HA

# 13. (Opzionale) Verifica cluster K3S
kubectl --kubeconfig ~/.kube/k3s-config get nodes
kubectl --kubeconfig ~/.kube/k3s-config get pods -A
```

**Nota:** `init-project.sh` automatizza la creazione di credenziali e token API. 
Vedi [docs/init-project.md](docs/init-project.md) per dettagli.

## Demo

Dopo aver installato il cluster con Kubespray, lancia lo script demo per verificare che tutto funzioni:

```bash
bash demo-cluster.sh
```

Lo script testa:
1. **Tetris** (service NodePort) → `http://192.168.0.120`
2. **Hello Kubernetes** (Deployment + LoadBalancer) → `http://192.168.0.121`
3. **Podinfo** (Deployment + LoadBalancer) → `http://192.168.0.122:9898`
4. **Registry interno** — verifica API tramite port-forward
5. **Push al registry** via nerdctl su SSH — testa che il registry locale funzioni

Esempio di output:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  DEMO CLUSTER KUBERNETES HOMELAB
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[INFO] 1. Tetris
[PASS] http://192.168.0.120 (Tetris)
[INFO] 2. Hello Kubernetes
[PASS] http://192.168.0.121 (Hello K8s)
[INFO] 3. Podinfo
[PASS] http://192.168.0.122:9898 (Podinfo)
[INFO] 4. Registry interno
[PASS] Registry 10.98.158.126:5000 — "repositories":["nginx"]
[INFO] 5. Registry push/pull
[PASS] Push nginx:alpine → 10.244.69.198:5000/nginx:test
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ✅ DEMO COMPLETATA
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## Documentazione

| Documento | Contenuto |
|-----------|-----------|
| [docs/init-project.md](docs/init-project.md) | Setup iniziale: Proxmox user/token, Vault, credenziali |
| [docs/cluster-configuration.md](docs/cluster-configuration.md) | Topologia cluster: 3 master + 3 worker, MetalLB, Dashboard |
| [docs/packer-multiple-distributions.md](docs/packer-multiple-distributions.md) | Packer: buildare Ubuntu 22.04 / 24.04 / Debian 13 / Rocky 9 templates |
| [docs/end-to-end.md](docs/end-to-end.md) | Guida completa: architettura, fasi, cheatsheet operativo |
| [docs/terraform-k8s-cluster.md](docs/terraform-k8s-cluster.md) | Terraform: provider, moduli, cloud-init, scalabilità |
| [docs/kubespray-deploy.md](docs/kubespray-deploy.md) | Kubespray: group_vars, Calico, gestione nodi |
| [docs/proxmox-api-user.md](docs/proxmox-api-user.md) | Utente API Proxmox: Vault, permessi, token |
| `k3s/deploy.sh` | Deploy K3S: install (single-node), join (HA), reset |

## Configurazione cluster

I parametri del cluster sono distribuiti in quattro file:

| File | Cosa configura | Generato da |
|------|----------------|-------------|
| `terraform/terraform.auto.tfvars` | Subnet K8s, gateway, IP base master/worker | `init-project.sh` |
| `terraform/terraform.tfvars` | Conteggio master/worker, risorse VM (CPU/RAM), storage | Manuale |
| `terraform-k3s/terraform.auto.tfvars` | Subnet K3S, gateway, IP pool | `init-project.sh` |
| `terraform-k3s/terraform.tfvars` | Conteggio nodi K3S (3), risorse VM | Manuale |
| `kubespray/inventory/homelab/group_vars/k8s_cluster/k8s-cluster.yml` | CIDR pod, kube-proxy (ipvs), DNS, NTP, registry, certificati | Manuale |
| `kubespray/inventory/homelab/group_vars/k8s_cluster/addons.yml` | Helm, Dashboard, Ingress-nginx, cert-manager, MetalLB, kube-vip | Manuale |

### Default

- **3 master** (HA with etcd) — configurabile con `control_plane_count` in `terraform/terraform.tfvars`
- **3 worker** — configurabile con `worker_count` in `terraform/terraform.tfvars`
- **Risorse per nodo**: 16GB RAM + 4 CPU — modificabili in `terraform/terraform.tfvars`
- **Storage**: 30GB disco per master, 50GB per worker
- **Subnet Kubernetes**: `192.168.0.0/24` — configurabile in `init-project.sh`, salvato in `terraform/terraform.auto.tfvars`
- **Gateway**: `192.168.0.1` — configurabile in `init-project.sh`
- **Master IP**: primo da `.150` (es. `.150`, `.151`, `.152`) — configurabile in `init-project.sh`
- **Worker IP**: primo da `.155` (es. `.155`, `.156`, `.157`) — configurabile in `init-project.sh`
- **kube-vip**: `192.168.0.80` (VIP control plane via ARP)
- **Pod subnet**: `10.244.0.0/16`
- **Service subnet**: `10.96.0.0/12`
- **Load balancer**: MetalLB con range `192.168.0.120-192.168.0.135`

### Default K3S

- **3 server** (HA con embedded etcd) — configurabile con `k3s_count` in `terraform-k3s/terraform.tfvars`
- **Risorse per nodo**: 16GB RAM + 4 CPU — modificabili in `terraform-k3s/terraform.tfvars`
- **Storage**: ereditato dal template (32GB)
- **Subnet K3S**: `192.168.0.0/24` — stessa subnet K8s
- **Gateway**: `192.168.0.1`
- **K3S VM IP**: primo da `.160` (es. `.160`, `.161`, `.162`) — configurabile in `terraform-k3s/terraform.tfvars`
- **VM ID**: primo da `44777` (es. `44777`, `44778`, `44779`) — configurabile in `terraform-k3s/terraform.tfvars`
- **Tutti i nodi** sono control plane + worker (nessun taint NoSchedule)
