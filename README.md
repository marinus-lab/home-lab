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

# 2. Inizializzazione — crea credenziali Proxmox e file di config
bash init-project.sh
# Domande: IP Proxmox, password root, nome automation user, password API, password Vault

# 3. Verifica
bash verify-init.sh
# Controlla: file di config, vault, connessione API Proxmox, token

# 4. (Opzionale) Personalizza topologia cluster
vim terraform/terraform.tfvars  # modifica control_plane_count, worker_count, risorse

# 5. Packer — build template VM
cd packer && ./build.sh

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
| [docs/end-to-end.md](docs/end-to-end.md) | Guida completa: architettura, fasi, cheatsheet operativo |
| [docs/packer-ubuntu-base.md](docs/packer-ubuntu-base.md) | Template Packer: autoinstall Ubuntu, boot_command, cleanup |
| [docs/terraform-k8s-cluster.md](docs/terraform-k8s-cluster.md) | Terraform: provider, moduli, cloud-init, scalabilità |
| [docs/kubespray-deploy.md](docs/kubespray-deploy.md) | Kubespray: group_vars, Calico, gestione nodi |
| [PROXMOX_API_USER_DOC.md](PROXMOX_API_USER_DOC.md) | Utente API Proxmox: Vault, permessi, token |

## Configurazione cluster

I parametri del cluster sono concentrati in tre file:

| File | Cosa configura |
|------|----------------|
| `terraform/terraform.tfvars` | IP nodi, sizing VM, conteggio master/worker |
| `kubespray/inventory/homelab/group_vars/k8s_cluster/k8s-cluster.yml` | Versione K8s, CIDR, proxy mode |
| `kubespray/inventory/homelab/group_vars/k8s_cluster/addons.yml` | Helm, MetalLB, Ingress, Cert-manager |

### Default

- **1 master** (minimal) — passare a 3 per HA: `control_plane_count = 3`
- **2 worker** — scalabile incrementando `worker_count`
- **Pod subnet**: `10.244.0.0/16`
- **Service subnet**: `10.96.0.0/12`
- **Rete**: `192.168.1.0/24`, master da `.210`, worker da `.220`
