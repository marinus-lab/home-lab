# Homelab Kubernetes su Proxmox

Infrastructure-as-Code per un cluster Kubernetes su Proxmox VE, costruito con Packer, Terraform e Kubespray.

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

# 4. Installa tutto il tooling (Packer, Terraform, Ansible, kubectl, ...)
bash setup-bastion.sh

# 5. Configura credenziali Proxmox, rete K8s e vault cifrato
bash init-project.sh

# 6. Ora sei pronto per il Quick start qui sotto
```

## Stack

| Tool | Versione | Ruolo |
|------|----------|-------|
| Proxmox VE | 7.x / 8.x | Hypervisor |
| Packer | ≥ 1.9 | Build template VM (Ubuntu 22.04/24.04, Rocky 9) |
| Terraform | ≥ 1.5 | Provisioning VM dal template |
| Kubespray | latest | Installazione Kubernetes |
| Kubernetes | v1.30.4 | Container orchestration |
| Calico | bundled | CNI (overlay IPIP) |
| containerd | bundled | Container runtime |
| MetalLB | latest | Load balancer bare-metal (Layer 2) |
| Kubernetes Dashboard | latest | UI monitoraggio cluster |

## Prerequisiti di rete

La fase **Packer** (build template VM) richiede:

- **Server DHCP attivo** sulla rete Proxmox — la VM di build riceve un IP temporaneo via DHCP durante l'installazione automatica da ISO. Dopo il clone con Terraform, i nodi K8s usano invece IP statici assegnati via cloud-init.
- **Bastion raggiungibile dalla rete VM** — Packer avvia un server HTTP temporaneo (porta 8613+) dal quale l'installer scarica la configurazione kickstart/autoinstall. Il bastion e la VM devono essere sulla stessa rete o comunque instradabili.

## Architettura

```
Bastion ──API──▶ Proxmox VE
                    │
                    ├─ Template VMID 9000  (Packer)
                    │       │
                    │       ├─ clone ──▶ k8s-master-1  192.168.1.210  (16GB RAM, 4 CPU)
                    │       ├─ clone ──▶ k8s-master-2  192.168.1.211  (16GB RAM, 4 CPU)
                    │       ├─ clone ──▶ k8s-master-3  192.168.1.212  (16GB RAM, 4 CPU)
                    │       ├─ clone ──▶ k8s-worker-1  192.168.1.220  (16GB RAM, 4 CPU)
                    │       ├─ clone ──▶ k8s-worker-2  192.168.1.221  (16GB RAM, 4 CPU)
                    │       └─ clone ──▶ k8s-worker-3  192.168.1.222  (16GB RAM, 4 CPU)
                    │
Bastion ──SSH──▶ 6 nodi K8s  (Kubespray installa il cluster HA)
                    └─ MetalLB: 192.168.0.120-192.168.0.135 (load balancing)
```

**Topologia cluster:**
- **3 nodi Control Plane** (HA etcd): k8s-master-1/2/3
- **3 nodi Worker**: k8s-worker-1/2/3
- **Totale**: 6 VM, ognuna con 16GB RAM + 4 CPU

## Struttura del repository

```
home-lab/
├── init-project.sh                        # Setup iniziale: credenziali, utente API, token, storage
├── verify-init.sh                         # Verifica post-init: file, vault, token, storage, dipendenze
├── setup-bastion.sh                       # Installa tooling sul bastion (tmux dashboard)
├── create_proxmox_user.yml                # Playbook Ansible alternativo per utente Proxmox
├── requirements.yml                       # Dipendenze Ansible Galaxy (community.general)
│
├── packer/                                # Build template VM (Ubuntu 22.04, Ubuntu 24.04, Rocky 9)
│   ├── variables.pkr.hcl                  # Variabili condivise (Proxmox, VM, storage, SSH)
│   ├── packer.pkrvars.hcl*                # Credenziali Packer (*in .gitignore)
│   ├── packer.pkrvars.hcl.example         # Template credenziali
│   ├── ubuntu-22.04.pkr.hcl               # Source + build Ubuntu 22.04 LTS
│   ├── ubuntu-24.04.pkr.hcl               # Source + build Ubuntu 24.04 LTS
│   ├── rocky-9.pkr.hcl                    # Source + build Rocky Linux 9
│   ├── build.sh                           # Menu interattivo per buildare le 3 distro
│   ├── download-isos.sh                   # Scarica/carica ISO su Proxmox via API
│   ├── http/
│   │   ├── ubuntu-user-data.tpl           # Template cloud-config autoinstall Ubuntu
│   │   ├── rocky-ks.cfg.tpl               # Template kickstart Rocky 9
│   │   └── meta-data                      # cloud-init metadata
│   └── scripts/
│       └── install-tools.sh               # Provisioner: apt update/upgrade + cleanup
│
├── terraform/                             # Provisioning VM cluster K8s
│   ├── main.tf                            # Provider proxmox (bpg), locals (SSH, CIDR)
│   ├── variables.tf                       # Variabili: Proxmox, rete, storage, master/worker
│   ├── k8s-cluster.tf                     # Core: topologia dinamica, moduli VM, inventory
│   ├── outputs.tf                         # IP nodi, inventory path, comandi SSH
│   ├── terraform.tfvars                   # Config cluster (tracciato: topologia, risorse)
│   ├── terraform.tfvars.example           # Template completo con tutti i parametri
│   ├── terraform.auto.tfvars*             # Credenziali + rete (*in .gitignore, da init-project.sh)
│   ├── terraform.auto.tfvars.example      # Template credenziali
│   ├── modules/proxmox-vm/                # Modulo riutilizzabile per singola VM
│   │   ├── main.tf                        # Clone, cloud-init, disco, rete, QEMU agent
│   │   ├── variables.tf                   # 18 variabili (nome, risorse, rete, SSH)
│   │   └── outputs.tf                     # IP, nome, VM ID
│   └── templates/
│       └── kubespray-inventory.tftpl      # Template Ansible inventory per Kubespray
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
│               ├── k8s-cluster.yml        # Versione K8s, CIDR, kube-proxy, certificati
│               ├── k8s-net-plugin.yml     # Calico IPIP, MTU, bird backend
│               └── addons.yml             # Helm, Metrics Server, Dashboard, MetalLB
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
# 1. Bastion — installa tutto il tooling
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
# Supporta: Ubuntu 22.04 LTS, Ubuntu 24.04 LTS, Rocky Linux 9
./build.sh    # Menu interattivo per scegliere distribuzione
# Oppure:
# ./build.sh ubuntu-22.04
# ./build.sh ubuntu-24.04
# ./build.sh rocky-9

# 7. Terraform — crea le VM
cd ../terraform && terraform apply

# 8. Kubespray — installa Kubernetes
cd ../kubespray && ./deploy.sh

# 9. Verifica
kubectl get nodes
kubectl get svc -A  # verifica MetalLB
```

**Nota:** `init-project.sh` automatizza la creazione di credenziali e token API. 
Vedi [docs/init-project.md](docs/init-project.md) per dettagli.

## Documentazione

| Documento | Contenuto |
|-----------|-----------|
| [docs/init-project.md](docs/init-project.md) | Setup iniziale: Proxmox user/token, Vault, credenziali |
| [docs/cluster-configuration.md](docs/cluster-configuration.md) | Topologia cluster: 3 master + 3 worker, MetalLB, Dashboard |
| [docs/packer-multiple-distributions.md](docs/packer-multiple-distributions.md) | Packer: buildare Ubuntu 22.04 / 24.04 / Rocky 9 templates |
| [docs/end-to-end.md](docs/end-to-end.md) | Guida completa: architettura, fasi, cheatsheet operativo |
| [docs/terraform-k8s-cluster.md](docs/terraform-k8s-cluster.md) | Terraform: provider, moduli, cloud-init, scalabilità |
| [docs/kubespray-deploy.md](docs/kubespray-deploy.md) | Kubespray: group_vars, Calico, gestione nodi |
| [docs/proxmox-api-user.md](docs/proxmox-api-user.md) | Utente API Proxmox: Vault, permessi, token |

## Configurazione cluster

I parametri del cluster sono distribuiti in quattro file:

| File | Cosa configura | Generato da |
|------|----------------|-------------|
| `terraform/terraform.auto.tfvars` | Subnet K8s, gateway, IP base master/worker | `init-project.sh` |
| `terraform/terraform.tfvars` | Conteggio master/worker, risorse VM (CPU/RAM), storage | Manuale |
| `kubespray/inventory/homelab/group_vars/k8s_cluster/k8s-cluster.yml` | Versione K8s, CIDR pod, proxy mode | Manuale |
| `kubespray/inventory/homelab/group_vars/k8s_cluster/addons.yml` | Helm, MetalLB, Ingress, Dashboard | Manuale |

### Default

- **3 master** (HA with etcd) — configurabile con `control_plane_count` in `terraform/terraform.tfvars`
- **3 worker** — configurabile con `worker_count` in `terraform/terraform.tfvars`
- **Risorse per nodo**: 16GB RAM + 4 CPU — modificabili in `terraform/terraform.tfvars`
- **Storage**: 30GB disco per master, 50GB per worker
- **Subnet Kubernetes**: `192.168.0.0/24` — configurabile in `init-project.sh`, salvato in `terraform/terraform.auto.tfvars`
- **Gateway**: `192.168.0.1` — configurabile in `init-project.sh`
- **Master IP**: primo da `.210` (es. `.210`, `.211`, `.212`) — configurabile in `init-project.sh`
- **Worker IP**: primo da `.220` (es. `.220`, `.221`, `.222`) — configurabile in `init-project.sh`
- **Pod subnet**: `10.244.0.0/16`
- **Service subnet**: `10.96.0.0/12`
- **Load balancer**: MetalLB con range `192.168.0.120-192.168.0.135`
