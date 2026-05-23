# Homelab Kubernetes su Proxmox

Infrastructure-as-Code per un cluster Kubernetes su Proxmox VE, costruito con Packer, Terraform e Kubespray.

## Stack

| Tool | Versione | Ruolo |
|------|----------|-------|
| Proxmox VE | 7.x / 8.x | Hypervisor |
| Packer | ≥ 1.9 | Build template VM Ubuntu 22.04 |
| Terraform | ≥ 1.5 | Provisioning VM dal template |
| Kubespray | latest | Installazione Kubernetes |
| Kubernetes | v1.30.4 | Container orchestration |
| Calico | bundled | CNI (overlay IPIP) |
| containerd | bundled | Container runtime |
| MetalLB | latest | Load balancer bare-metal (Layer 2) |
| Kubernetes Dashboard | latest | UI monitoraggio cluster |

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
├── init-project.sh             # Setup iniziale (crea credenziali + token)
├── verify-init.sh              # Verifica configurazione
├── setup-bastion.sh            # Installa tooling sul bastion
├── packer/                     # Build template Ubuntu 22.04
│   └── packer.pkrvars.hcl*     # Credenziali Packer (*in .gitignore)
├── terraform/                  # Provisioning VM cluster K8s
│   ├── terraform.tfvars        # Configurazione cluster (tracciato)
│   ├── terraform.auto.tfvars*  # Credenziali Proxmox (*in .gitignore, auto-generato)
│   └── terraform.auto.tfvars.example  # Template credenziali
├── kubespray/                  # Deploy Kubernetes
├── ansible/playbooks/          # Configurazione base VM
└── docs/                       # Documentazione dettagliata
```

**Note su credenziali e Git:**
- ✅ File tracciati: `terraform.tfvars`, `group_vars/all.yml` (Vault cifrato), documentazione
- ❌ File ignorati: `*.auto.tfvars`, `packer.pkrvars.hcl` (contengono token)
- 🔐 File `.example`: template per referenza e setup manuale

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

# 5. Packer — build template VM
# Supporta: Ubuntu 22.04 LTS, Ubuntu 24.04 LTS, Rocky Linux 9
cd packer && ./build.sh    # Menu interattivo per scegliere distribuzione
# Oppure:
# ./build.sh ubuntu-22.04
# ./build.sh ubuntu-24.04
# ./build.sh rocky-9

# 6. Terraform — crea le VM
cd ../terraform && terraform apply

# 7. Kubespray — installa Kubernetes
cd ../kubespray && ./deploy.sh

# 8. Verifica
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
