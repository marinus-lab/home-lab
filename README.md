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

## Architettura

```
Bastion ──API──▶ Proxmox VE
                    │
                    ├─ Template VMID 9000  (Packer)
                    │       │
                    │       ├─ clone ──▶ k8s-master-1  192.168.1.210
                    │       ├─ clone ──▶ k8s-worker-1  192.168.1.220
                    │       └─ clone ──▶ k8s-worker-2  192.168.1.221
                    │
Bastion ──SSH──▶ nodi K8s  (Kubespray installa il cluster)
```

## Struttura del repository

```
home-lab/
├── setup-bastion.sh            # Installa il tooling sul bastion
├── create_proxmox_user.yml     # Crea l'utente API Proxmox (Ansible)
├── packer/                     # Build template Ubuntu 22.04
├── terraform/                  # Provisioning VM cluster K8s
├── kubespray/                  # Deploy Kubernetes
├── ansible/playbooks/          # Configurazione base VM
└── docs/                       # Documentazione dettagliata
```

## Quick start

```bash
# 1. Bastion — installa tutto il tooling
bash setup-bastion.sh

# 2. Proxmox — crea utente e token API
ansible-playbook create_proxmox_user.yml --ask-vault-pass \
  -e "proxmox_host=<IP_PROXMOX>"

# 3. Packer — build template VM
cd packer
cp packer.pkrvars.hcl.example packer.pkrvars.hcl  # compila con le tue credenziali
PACKER_ARGS="-var-file=packer.pkrvars.hcl" ./build.sh

# 4. Terraform — crea le VM
cd ../terraform
cp terraform.tfvars.example terraform.tfvars       # compila con le tue credenziali
terraform init && terraform apply

# 5. Kubespray — installa Kubernetes
cd ../kubespray
cp ../terraform/generated/kubespray-inventory.ini inventory/homelab/hosts.ini
./deploy.sh

# 6. Verifica
kubectl get nodes
```

## Documentazione

| Documento | Contenuto |
|-----------|-----------|
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
