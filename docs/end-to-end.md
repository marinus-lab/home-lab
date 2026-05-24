# Homelab Kubernetes su Proxmox — Guida end-to-end

## Indice

1. [Architettura del progetto](#architettura-del-progetto)
2. [Prerequisiti](#prerequisiti)
3. [Fase 0 — Setup del bastion](#fase-0--setup-del-bastion)
4. [Fase 1 — Utente API Proxmox](#fase-1--utente-api-proxmox)
5. [Fase 2 — Template VM con Packer](#fase-2--template-vm-con-packer)
6. [Fase 3 — Infrastruttura con Terraform](#fase-3--infrastruttura-con-terraform)
7. [Fase 4 — Cluster Kubernetes con Kubespray](#fase-4--cluster-kubernetes-con-kubespray)
8. [Fase 5 — Verifica post-deploy](#fase-5--verifica-post-deploy)
9. [Struttura del repository](#struttura-del-repository)
10. [Riferimenti ai doc di dettaglio](#riferimenti-ai-doc-di-dettaglio)

---

## Architettura del progetto

```
┌─────────────────────────────────────────────────────────────────────┐
│  HOMELAB NETWORK  (es. 192.168.1.0/24)                              │
│                                                                     │
│  ┌──────────────┐        ┌─────────────────────────────────────┐   │
│  │   BASTION    │        │            PROXMOX VE               │   │
│  │ 192.168.1.10 │──API──▶│                                     │   │
│  │              │        │  ┌──────────────────────────────┐   │   │
│  │ Terraform    │        │  │  Template VM (Packer)        │   │   │
│  │ Packer       │──SSH──▶│  │  ubuntu-22.04-base  (Packer) │   │   │
│  │ Ansible      │        │  └──────────┬───────────────────┘   │   │
│  │ Kubespray    │        │             │ clone (Terraform)      │   │
│  └──────────────┘        │  ┌──────────▼───────────────────┐   │   │
│         │                │  │  k8s-master-1  VMID 201      │   │   │
│         │                │  │  192.168.1.210               │   │   │
│         │ ansible        │  ├──────────────────────────────┤   │   │
│         └───────────────▶│  │  k8s-worker-1  VMID 211      │   │   │
│                          │  │  192.168.1.220               │   │   │
│                          │  ├──────────────────────────────┤   │   │
│                          │  │  k8s-worker-2  VMID 212      │   │   │
│                          │  │  192.168.1.221               │   │   │
│                          │  └──────────────────────────────┘   │   │
│                          └─────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘

KUBERNETES CLUSTER (overlay)
  Pod subnet:     10.244.0.0/16   (Calico IPIP)
  Service subnet: 10.96.0.0/12
```

### Toolchain

| Tool | Ruolo | Dove gira |
|------|-------|-----------|
| **Packer** | Crea il template VM (multi-distribuzione) su Proxmox | Bastion |
| **Terraform** | Clona il template e crea le VM K8s | Bastion |
| **configure-cluster.sh** | Wizard interattivo per topologia cluster (master/worker count, IP) | Bastion |
| **Ansible / Kubespray** | Installa Kubernetes sulle VM | Bastion → nodi K8s |
| **cloud-init** | Configura IP, hostname, SSH key al primo boot | Ogni VM |
| **Calico** | Rete pod-to-pod (IPIP overlay) | Cluster K8s |
| **containerd** | Container runtime | Ogni nodo K8s |

---

## Prerequisiti

### Hardware

| Componente | Minimo | Consigliato |
|------------|--------|-------------|
| Proxmox VE | 1 nodo, 16 GB RAM, 200 GB storage | 1+ nodi, 32 GB RAM, SSD |
| Bastion | VM o fisico con 2 GB RAM, 20 GB disco | Debian/Ubuntu 22.04 |

### Software su Proxmox

- Proxmox VE 7.x o 8.x
- Storage `local-lvm` disponibile (o adattare `storage_pool`)
- Bridge `vmbr0` configurato con accesso LAN

### Conoscenze

- Accesso SSH a Proxmox con utente `root`
- IP del nodo Proxmox raggiungibile dal bastion
- Range di IP liberi nella LAN per i nodi K8s (almeno 3)

---

## Fase 0 — Setup del bastion

Il bastion è la macchina da cui si controlla tutto. Può essere una VM su Proxmox, un server fisico o un PC nella stessa rete.

### Esecuzione

```bash
# Clona il repository sul bastion
git clone <repo-url> ~/home-lab
cd ~/home-lab

# Avvia lo script di setup (richiede Debian/Ubuntu)
bash setup-bastion.sh
```

### Cosa installa

Lo script usa una dashboard tmux per mostrare il progresso in tempo reale:

| Fase | Cosa viene installato |
|------|-----------------------|
| 1 | OpenJDK 17 |
| 2 | Dipendenze sistema (curl, git, python3, jq, tmux, htop...) |
| 3 | Vim con tema desert e plugin Terraform |
| 4 | Node.js 22 |
| 5 | OpenCode AI Agent |
| 6 | OpenClaude |
| 7 | Ansible + modulo community.proxmox + proxmoxer |
| 8 | Terraform + Packer (HashiCorp APT repo) |
| 9 | **Venv Python `~/kubespray-env`** con dipendenze Kubespray |
| 10 | Chiave SSH RSA 4096-bit in `~/.ssh/id_rsa` |
| 11 | less + Pygmentize (syntax highlight nei file) |

### Verifica

```bash
terraform --version    # >= 1.5
packer --version       # >= 1.9
ansible --version      # >= 2.14
python3 --version      # >= 3.10
ls ~/.ssh/id_rsa.pub   # chiave SSH generata
```

---

## Fase 1 — Utente API Proxmox

Terraform e Packer si autenticano su Proxmox tramite **API token** — mai con username/password direttamente.

### Configurazione credenziali vault

```bash
# Crea il file secrets (gitignored)
cp group_vars/all.yml group_vars/all.vault.yml
ansible-vault encrypt_string '<password-root-proxmox>' \
  --name vault_proxmox_root_pw >> group_vars/all.yml
ansible-vault encrypt_string '<password-utente-automation>' \
  --name vault_automation_user_pw >> group_vars/all.yml
```

### Creazione utente e token

```bash
# Installa la collezione Ansible richiesta
ansible-galaxy collection install -r requirements.yml

# Crea l'utente automation@pve con ruolo PVEAdmin
# e genera il token API
ansible-playbook create_proxmox_user.yml \
  --ask-vault-pass \
  -e "proxmox_host=192.168.1.10"
```

Il playbook mostra il token generato — **salvarlo subito**, non è recuperabile:

```
TASK [Display API token] *****
ok: [localhost] => {
    "msg": "automation@pve!packer=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
}
```

### Esportare le credenziali

Aggiungere al `~/.bashrc` (o esportare nella sessione corrente):

```bash
export PROXMOX_URL="https://192.168.1.10:8006/api2/json"
export PROXMOX_TOKEN_ID="automation@pve!terraform"
export PROXMOX_TOKEN_SECRET="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

> Lo stesso token viene usato da Packer (step 2) e da Terraform (step 3).
> Se si preferisce separare i permessi, creare due token distinti:
> `automation@pve!packer` e `automation@pve!terraform`.

---

## Fase 2 — Template VM con Packer

Packer scarica l'ISO della distribuzione scelta, avvia una VM temporanea su Proxmox, installa il sistema in modalità non interattiva (autoinstall/preseed/kickstart) e salva il risultato come **template** (es. VMID 9002 per Ubuntu 24.04).

### Configurazione

```bash
cd packer

# Copia il file variabili di esempio
cp packer.pkrvars.hcl.example packer.pkrvars.hcl

# Modifica con i tuoi valori
vim packer.pkrvars.hcl
```

Valori da personalizzare in `packer.pkrvars.hcl`:

```hcl
proxmox_url          = "https://192.168.1.10:8006/api2/json"
proxmox_token_id     = "automation@pve!packer"
proxmox_token_secret = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
proxmox_node         = "pve"
template_storage_pool = "local-lvm"
```

### Build

```bash
# Le credenziali possono essere passate via env vars (già esportate)
# oppure tramite il file vars
PACKER_ARGS="-var-file=packer.pkrvars.hcl" ./build.sh

# Con password personalizzate
UBUNTU_PASSWORD="mysecurepass" \
ROOT_PASSWORD="mysecureroot" \
PACKER_ARGS="-var-file=packer.pkrvars.hcl" \
./build.sh
```

### Cosa succede durante la build

```
1. Packer crea una VM (VMID es. 9002 per Ubuntu 24.04) su Proxmox via API
2. Monta l'ISO Ubuntu 22.04 e avvia il boot
3. Invia la sequenza GRUB via VNC:
      c → linux /casper/vmlinuz --- autoinstall ds=nocloud-net;s=http://<bastion>:<port>/
4. Ubuntu scarica http/user-data dal bastion e installa automaticamente:
      - partizionamento LVM
      - utente ubuntu con sudo NOPASSWD
      - root SSH abilitato (password: "packer")
      - qemu-guest-agent abilitato
5. Packer si connette via SSH come root
6. Esegue scripts/install-tools.sh  → apt upgrade
7. Esegue ansible/playbooks/base.yml con packer_build=true:
      - abilita qemu-guest-agent
      - cloud-init clean (reset per il clone)
      - rimuove SSH host keys
      - svuota machine-id
8. Converte la VM in template → pronto per clonazione con Terraform
```

### Durata stimata

- Download ISO: 5-15 min (dipende dalla connessione)
- Installazione Ubuntu: 10-15 min
- Provisioning Ansible: 2-3 min
- **Totale: 20-35 minuti**

### Verifica

```bash
# Il template deve comparire nella lista VM di Proxmox
ssh root@192.168.1.10 "qm list | grep 9000"
# 9000 ubuntu-22.04-base  stopped  ...  template
```

---

## Fase 3 — Infrastruttura con Terraform

Terraform clona il template VM (es. 9002 per Ubuntu 24.04) e crea le VM del cluster Kubernetes, iniettando IP statici, hostname e chiave SSH tramite cloud-init.

### Configurazione

```bash
cd ../terraform

# Copia il file variabili
cp terraform.tfvars.example terraform.tfvars

# Modifica con i tuoi valori
vim terraform.tfvars
```

Valori minimi da impostare:

```hcl
proxmox_url          = "https://192.168.1.10:8006/api2/json"
proxmox_token_id     = "automation@pve!terraform"
proxmox_token_secret = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

# Adatta alla tua rete
k8s_subnet    = "192.168.1.0/24"
k8s_gateway   = "192.168.1.1"

# Assicurarsi che questi IP siano liberi nella LAN
# master: 192.168.1.210
# worker: 192.168.1.220, 192.168.1.221
master_ip_start = 210
worker_ip_start = 220
```

### Configurazione topologia (opzionale)

```bash
# Wizard interattivo per numero master/worker, subnet, IP
bash configure-cluster.sh
```

Se preferisci la configurazione manuale, edita direttamente `terraform.tfvars`.

### Deploy

```bash
# Inizializza il provider bpg/proxmox
terraform init

# Verifica cosa verrà creato (nessuna modifica)
terraform plan

# Crea le VM
terraform apply
```

### Cosa crea Terraform

Con la configurazione di default (`control_plane_count=3`, `worker_count=3`):

| VM | VMID | IP | CPU | RAM | Disco |
|----|------|----|-----|-----|-------|
| k8s-master-1 | 201 | 192.168.1.210 | 2 | 2 GB | 30 GB |
| k8s-master-2 | 202 | 192.168.1.211 | 2 | 2 GB | 30 GB |
| k8s-master-3 | 203 | 192.168.1.212 | 2 | 2 GB | 30 GB |
| k8s-worker-1 | 211 | 192.168.1.220 | 4 | 4 GB | 50 GB |
| k8s-worker-2 | 212 | 192.168.1.221 | 4 | 4 GB | 50 GB |
| k8s-worker-3 | 213 | 192.168.1.222 | 4 | 4 GB | 50 GB |

Per ogni VM, Terraform:
1. Clona (full clone) il template Packer
2. Ridimensiona il disco se necessario
3. Scrive i dati cloud-init nel drive (IP, gateway, DNS, SSH key)
4. Avvia la VM → cloud-init configura la rete al boot

Al termine genera `generated/kubespray-inventory.ini`.

### Output

```bash
terraform output all_nodes
# {
#   "k8s-master-1" = "192.168.1.210"
#   "k8s-worker-1" = "192.168.1.220"
#   "k8s-worker-2" = "192.168.1.221"
# }

terraform output ssh_command_examples
# {
#   "k8s-master-1" = "ssh ubuntu@192.168.1.210"
#   ...
# }
```

### Verifica connettività

```bash
# Testare SSH su tutti i nodi prima di procedere con Kubespray
ssh ubuntu@192.168.1.210 "hostname && uptime"
ssh ubuntu@192.168.1.220 "hostname && uptime"
ssh ubuntu@192.168.1.221 "hostname && uptime"
```

### Durata stimata

- Clone + resize: 1-3 min per VM
- Boot + cloud-init: 1-2 min per VM
- **Totale: 5-10 minuti**

---

## Fase 4 — Cluster Kubernetes con Kubespray

Kubespray installa Kubernetes su tutti i nodi tramite Ansible, a partire dall'inventory generato da Terraform.

### Deploy

```bash
cd ../kubespray
./deploy.sh
```

Il `deploy.sh`:
1. Copia l'inventory da `terraform/generated/kubespray-inventory.ini` se più recente
2. Verifica la connettività SSH verso tutti i nodi
3. Clona `kubernetes-sigs/kubespray` in `~/kubespray` (solo la prima volta)
4. Attiva il venv `~/kubespray-env`
5. Lancia `ansible-playbook cluster.yml` con l'inventory homelab

### Cosa installa Kubespray

Su ogni nodo:
- **containerd** — container runtime
- **kubelet** — agente K8s
- **CNI plugins** — interfacce di rete container

Solo sui master:
- **etcd** — datastore del cluster
- **kube-apiserver** — API K8s
- **kube-controller-manager**
- **kube-scheduler**
- **calico-kube-controllers**

Su tutti i nodi:
- **calico-node** — networking pod (overlay IPIP)
- **kube-proxy** — bilanciamento servizi (modalità ipvs)
- **CoreDNS** (solo master)

Addon installati:
- **Helm** — package manager K8s
- **Metrics Server** — `kubectl top` e HPA

Al termine, il kubeconfig viene scaricato in `~/.kube/config` sul bastion.

### Durata stimata

- Download binari (prima volta): 10-20 min
- Installazione e configurazione: 15-20 min
- **Totale: 25-40 minuti**

---

## Fase 5 — Verifica post-deploy

### Stato del cluster

```bash
# Tutti i nodi devono essere Ready
kubectl get nodes -o wide
# NAME           STATUS   ROLES           AGE   VERSION   INTERNAL-IP
# k8s-master-1   Ready    control-plane   5m    1.36.0   192.168.1.210
# k8s-worker-1   Ready    <none>          3m    1.36.0   192.168.1.220
# k8s-worker-2   Ready    <none>          3m    1.36.0   192.168.1.221

# Tutti i pod di sistema devono essere Running o Completed
kubectl get pods -A
# NAMESPACE     NAME                                   READY   STATUS
# kube-system   calico-kube-controllers-...            1/1     Running
# kube-system   calico-node-...                        1/1     Running  (uno per nodo)
# kube-system   coredns-...                            1/1     Running
# kube-system   etcd-k8s-master-1                      1/1     Running
# kube-system   kube-apiserver-k8s-master-1            1/1     Running
# kube-system   kube-controller-manager-k8s-master-1   1/1     Running
# kube-system   kube-proxy-...                         1/1     Running  (uno per nodo)
# kube-system   kube-scheduler-k8s-master-1            1/1     Running
# kube-system   metrics-server-...                     1/1     Running
```

### Test funzionale

```bash
# Versione K8s
kubectl version --short

# Metriche nodi (richiede metrics-server)
kubectl top nodes

# Deploy test
kubectl create deployment nginx --image=nginx --replicas=2
kubectl wait --for=condition=available deployment/nginx --timeout=60s
kubectl get pods -o wide

# Verifica distribuzione sui worker
# I pod devono essere schedulati sui nodi worker, non sul master

# Cleanup
kubectl delete deployment nginx
```

### Verifica rete (Calico)

```bash
# Pod di test su due nodi diversi
kubectl run test-a --image=busybox --overrides='{"spec":{"nodeName":"k8s-worker-1"}}' \
  -- sleep 3600
kubectl run test-b --image=busybox --overrides='{"spec":{"nodeName":"k8s-worker-2"}}' \
  -- sleep 3600

# Ottieni IP del pod test-a
POD_A_IP=$(kubectl get pod test-a -o jsonpath='{.status.podIP}')

# Testa la connettività tra nodi (overlay IPIP)
kubectl exec test-b -- ping -c 3 "$POD_A_IP"
# Deve rispondere — verifica che il tunnel IPIP funzioni

# Cleanup
kubectl delete pod test-a test-b
```

---

## Struttura del repository

```
home-lab/
│
├── setup-bastion.sh                    # Fase 0: installa tooling sul bastion
├── init-project.sh                     # Fase 1: inizializzazione progetto
├── verify-init.sh                      #   verifica configurazione
├── create_proxmox_user.yml             #   playbook creazione utente API
├── requirements.yml                    #   dipendenze Ansible Galaxy
├── group_vars/all.yml                  #   secrets Ansible Vault
│
├── packer/                             # Fase 2: build template VM
│   ├── build.sh                        #   script di avvio (interattivo)
│   ├── download-isos.sh                #   pre-download ISO su Proxmox
│   ├── variables.pkr.hcl               #   variabili comuni
│   ├── ubuntu-22.04.pkr.hcl            #   template Ubuntu 22.04
│   ├── ubuntu-24.04.pkr.hcl            #   template Ubuntu 24.04
│   ├── debian-13.pkr.hcl               #   template Debian 13
│   ├── rocky-9.pkr.hcl                 #   template Rocky 9
│   ├── packer.pkrvars.hcl.example      #   esempio valori
│   ├── http/
│   │   ├── ubuntu-user-data.tpl        #   autoinstall Ubuntu (template)
│   │   ├── debian-preseed.cfg.tpl      #   preseed Debian
│   │   ├── rocky-ks.cfg.tpl            #   kickstart Rocky
│   │   └── meta-data                   #   richiesto dal protocollo nocloud
│   └── scripts/
│       └── install-tools.sh            #   apt/yum upgrade post-install
│
├── ansible/playbooks/
│   ├── base.yml                        #   cleanup template (Packer) + config base (post-clone)
│   └── proxmox_image_import.yml
│
├── terraform/                          # Fase 3: VM del cluster K8s
│   ├── main.tf                         #   provider bpg/proxmox
│   ├── variables.tf                    #   tutte le variabili
│   ├── k8s-cluster.tf                  #   topologia cluster + inventory
│   ├── configure-cluster.sh            #   wizard interattivo topologia
│   ├── outputs.tf                      #   IP, comandi SSH, path inventory
│   ├── terraform.tfvars.example        #   esempio valori
│   ├── templates/
│   │   └── kubespray-inventory.tftpl   #   template per hosts.ini
│   ├── generated/                      #   (gitignored) output post-apply
│   └── modules/proxmox-vm/             #   modulo VM riusabile
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
│
├── kubespray/                          # Fase 4: installazione Kubernetes
│   ├── deploy.sh                       #   script deploy/upgrade/remove/reset
│   ├── ansible.cfg                     #   config Ansible
│   └── inventory/homelab/
│       ├── hosts.ini                   #   generato da Terraform
│       └── group_vars/
│           ├── all/all.yml             #   K8s version, NTP, DNS
│           ├── all/containerd.yml      #   container runtime
│           └── k8s_cluster/
│               ├── k8s-cluster.yml     #   CIDR, proxy mode, certificati
│               ├── k8s-net-plugin.yml  #   Calico IPIP
│               └── addons.yml          #   Helm, Dashboard, MetalLB...
│
└── docs/
    ├── end-to-end.md                   #   guida completa
    ├── init-project.md                 #   setup automatico progetto
    ├── packer-ubuntu-base.md           #   dettagli Packer Ubuntu
    ├── packer-multiple-distributions.md #   build multi-distribuzione
    ├── terraform-k8s-cluster.md        #   dettagli Terraform
    ├── kubespray-deploy.md             #   dettagli Kubespray
    ├── cluster-configuration.md        #   topologia e addon
    └── proxmox-api-user.md             #   dettagli utente API
```

---

## Riferimenti ai doc di dettaglio

| Documento | Contenuto |
|-----------|-----------|
| [packer-ubuntu-base.md](packer-ubuntu-base.md) | Funzionamento autoinstall Ubuntu, boot_command GRUB, cleanup template, troubleshooting |
| [terraform-k8s-cluster.md](terraform-k8s-cluster.md) | Provider bpg/proxmox, for_each, cloud-init, scalabilità cluster, troubleshooting |
| [kubespray-deploy.md](kubespray-deploy.md) | group_vars, Calico IPIP, venv, gestione nodi, troubleshooting |
| [proxmox-api-user.md](proxmox-api-user.md) | Creazione utente API, Ansible Vault, permessi token |
| [init-project.md](init-project.md) | Inizializzazione automatica del progetto, token, Vault |
| [cluster-configuration.md](cluster-configuration.md) | Configurazione cluster, topologia, addon |
| [packer-multiple-distributions.md](packer-multiple-distributions.md) | Build multi-distribuzione (Rocky, Debian, Ubuntu) |

---

## Cheatsheet operativo

### Deploy completo (prima volta)

```bash
# 0. Bastion
bash setup-bastion.sh

# 1. Inizializzazione progetto (utente API + token + configurazione)
bash init-project.sh

# 2. Template Packer
cd packer && ./build.sh

# 3. Topologia cluster + VM Terraform
cd ../terraform
bash configure-cluster.sh              # wizard topologia (opzionale)
terraform init && terraform apply

# 4. Cluster Kubernetes (deploy.sh copia inventory automaticamente)
cd ../kubespray && ./deploy.sh

# 5. Verifica
kubectl get nodes
```

### Operazioni ricorrenti

```bash
# Aggiungere un worker
# → terraform.tfvars: worker_count = 3
cd terraform && terraform apply
cd ../kubespray && EXTRA_ARGS="--limit k8s-worker-3" ./deploy.sh

# Aggiornare Kubernetes
# → group_vars/all/all.yml: kube_version: 1.36.0
cd kubespray && ./deploy.sh upgrade

# Rimuovere un worker
kubectl drain k8s-worker-2 --ignore-daemonsets --delete-emptydir-data
kubectl delete node k8s-worker-2
cd kubespray && ./deploy.sh remove-node k8s-worker-2
# → terraform.tfvars: worker_count = 1
cd terraform && terraform apply

# Ricostruire il template Packer (es. Ubuntu 24.04)
ssh root@192.168.1.10 "qm destroy 9002"
cd packer && ./build.sh ubuntu-24.04

# Distruggere il cluster
cd terraform && terraform destroy
```

### Kubectl quick reference

```bash
kubectl get nodes -o wide              # stato nodi
kubectl get pods -A                    # tutti i pod
kubectl top nodes                      # utilizzo risorse
kubectl describe node k8s-worker-1     # dettagli nodo
kubectl logs -n kube-system <pod>      # log pod sistema
kubectl get events -A --sort-by='.lastTimestamp'  # eventi recenti
```
