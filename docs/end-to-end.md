# Homelab Kubernetes + K3S su Proxmox — Guida end-to-end

## Indice

1. [Architettura del progetto](#architettura-del-progetto)
2. [Prerequisiti](#prerequisiti)
3. [Fase 0 — Setup del bastion](#fase-0--setup-del-bastion)
4. [Fase 1 — Utente API Proxmox](#fase-1--utente-api-proxmox)
5. [Fase 2 — Template VM con Packer](#fase-2--template-vm-con-packer)
6. [Fase 3 — Infrastruttura con Terraform](#fase-3--infrastruttura-con-terraform)
7. [Fase 4 — Cluster Kubernetes con Kubespray](#fase-4--cluster-kubernetes-con-kubespray)
8. [Fase 5 — Cluster K3S (opzionale)](#fase-5--cluster-k3s-opzionale)
9. [Fase 6 — Verifica post-deploy](#fase-6--verifica-post-deploy)
10. [Struttura del repository](#struttura-del-repository)
11. [Riferimenti ai doc di dettaglio](#riferimenti-ai-doc-di-dettaglio)

---

## Architettura del progetto

```
┌────────────────────────────────────────────────────────────────────┐
│  HOMELAB NETWORK  (es. 192.168.1.0/24)                             │
│                                                                    │
│  ┌──────────────┐        ┌─────────────────────────────────────┐   │
│  │   BASTION    │        │            PROXMOX VE               │   │
│  │ 192.168.1.10 │──API──▶│                                     │   │
│  │              │        │  ┌──────────────────────────────┐   │   │
│  │ Terraform    │        │  │  Template VM (Packer)        │   │   │
│  │ Packer       │──SSH──▶│  │  ubuntu-22.04-base  (Packer) │   │   │
│  │ Ansible      │        │  └──────────┬───────────────────┘   │   │
│  │ Kubespray    │        │             │ clone (Terraform)     │   │
│  │ k3s          │        │  ┌──────────▼───────────────────┐   │   │
│  └──────────────┘        │  │  k8s-master-1  VMID 201      │   │   │
│         │                │  │  192.168.1.210               │   │   │
│         │ ansible        │  ├──────────────────────────────┤   │   │
│         ├───────────────▶│  │  k8s-worker-1  VMID 211      │   │   │
│         │                │  │  192.168.1.220               │   │   │
│         │ / k3s          │  ├──────────────────────────────┤   │   │
│         │ deploy.sh      │  │  k8s-worker-2  VMID 212      │   │   │
│         │                │  │  192.168.1.221               │   │   │
│         │                │  └──────────────────────────────┘   │   │
│         │                │  ┌──────────────────────────────┐   │   │
│         │                │  │  k3s-1  VMID 44777           │   │   │
│         │                │  │  192.168.1.160               │   │   │
│         │                │  ├──────────────────────────────┤   │   │
│         │                │  │  k3s-2  VMID 44778           │   │   │
│         │                │  │  192.168.1.161               │   │   │
│         │                │  ├──────────────────────────────┤   │   │
│         │                │  │  k3s-3  VMID 44779           │   │   │
│         │                │  │  192.168.1.162               │   │   │
│         │                │  └──────────────────────────────┘   │   │
│         │                └─────────────────────────────────────┘   │
│         └──────────── K3S (SSH / k3s/deploy.sh) ──────────────────▶│
│                                                                    │
└────────────────────────────────────────────────────────────────────┘

KUBERNETES CLUSTER (overlay)
  Pod subnet:     10.244.0.0/16   (Calico IPIP)
  Service subnet: 10.96.0.0/12
```

### Toolchain

| Tool | Ruolo | Dove gira |
|------|-------|-----------|
| **Packer** | Crea il template VM (multi-distribuzione) su Proxmox | Bastion |
| **Terraform** | Clona il template e crea le VM (K8s + K3S) | Bastion |
| **Ansible / Kubespray** | Installa Kubernetes sulle VM K8s | Bastion → nodi K8s |
| **k3s/deploy.sh** | Installa K3S sulle VM K3S (due fasi: single-node → HA) | Bastion → nodi K3S |
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
| 5 | GitHub Copilot CLI |
| 6 | Gemini CLI |
| 7 | OpenCode AI Agent |
| 8 | OpenClaude |
| 9 | Ansible + modulo community.proxmox + proxmoxer |
| 10 | Terraform + Packer (HashiCorp APT repo) |
| 11 | **Venv Python `~/kubespray-env`** con dipendenze Kubespray |
| 12 | Chiave SSH RSA 4096-bit in `~/.ssh/id_rsa` |
| 13 | less + Pygmentize (syntax highlight nei file) |

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
ansible-playbook ansible/playbooks/create_proxmox_user.yml \
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

> Sia il playbook `create_proxmox_user.yml` che `init-project.sh` creano **due token separati**:
> `automation@pve!packer` (per Packer) e `automation@pve!terraform` (per Terraform).
> Questo permette di ruotare/revocare i token indipendentemente.

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
# 9000 rocky-9-base  stopped  ...  template
```

---

## Fase 3 — Infrastruttura con Terraform

Due directory Terraform separate per i due cluster:

| Cluster | Directory | VM create | Comando |
|---------|-----------|-----------|---------|
| **K8s** (Kubespray) | `terraform/` | 3 master + 3 worker | `terraform apply -parallelism=2` |
| **K3S** (leggero) | `terraform-k3s/` | 3 server (opzionale) | `terraform apply -parallelism=2` |

### Cluster K8s (Kubespray)

Terraform clona il template VM e crea le VM del cluster Kubernetes, iniettando IP statici, hostname e chiave SSH tramite cloud-init.

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

### Deploy K8s

```bash
terraform init
terraform plan
terraform apply -parallelism=2
```

### Cosa crea Terraform per K8s

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

### Cluster K3S (opzionale)

Se desideri un cluster K3S separato dal K8s, crea le VM K3S con la configurazione dedicata:

```bash
# Vai nella directory terraform-k3s (usa lo stesso template VM e provider Proxmox)
cd ../terraform-k3s

# I file di configurazione sono generati da init-project.sh
# e già presenti in terraform.tfvars (topologia) e terraform.auto.tfvars (credenziali)

# Inizializza
terraform init

# Crea le 3 VM K3S (k3s-1, k3s-2, k3s-3)
terraform apply -parallelism=2
```

### Cosa crea Terraform per K3S

| VM | VMID | IP | CPU | RAM | Disco |
|----|------|----|-----|-----|-------|
| k3s-1 | 44777 | 192.168.1.160 | 4 | 16 GB | template (32 GB) |
| k3s-2 | 44778 | 192.168.1.161 | 4 | 16 GB | template (32 GB) |
| k3s-3 | 44779 | 192.168.1.162 | 4 | 16 GB | template (32 GB) |

Al termine genera `terraform-k3s/generated/k3s-inventory.ini` (poi copiato in `k3s/inventory.ini` da `k3s/deploy.sh`).

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

## Fase 5 — Cluster K3S (opzionale)

K3S è un Kubernetes leggero certificato CNCF, ideale per edge/IoT. Il cluster K3S è separato dal cluster K8s (Kubespray) e usa le VM create da `terraform-k3s/`.

### Deploy (due fasi)

La procedura si compone di due fasi per permettere la verifica intermedia:

```bash
cd ../k3s

# Fase 1: installa K3S su k3s-1 (single-node con cluster-init per embedded etcd)
./deploy.sh install

# Verifica
kubectl --kubeconfig ~/.kube/k3s-config get nodes

# Fase 2: unisce k3s-2 e k3s-3 per formare un cluster HA a 3 server
./deploy.sh join

# Verifica finale
kubectl --kubeconfig ~/.kube/k3s-config get nodes
```

### Cosa fa deploy.sh

- **`install`**: si connette a `k3s-1`, installa K3S con `--cluster-init` (embedded etcd), salva il token di join in `.k3s-token` e il kubeconfig in `~/.kube/k3s-config`
- **`join`**: si connette a `k3s-2` e `k3s-3`, legge il token da `.k3s-token`, unisce i nodi al cluster come server (control plane + worker, nessun taint `NoSchedule`)
- **`reset`**: esegue `k3s-uninstall.sh` su tutti e 3 i nodi

### Resoconto

Al termine avrai un cluster HA a 3 nodi K3S:

```bash
kubectl --kubeconfig ~/.kube/k3s-config get nodes -o wide
# NAME   STATUS   ROLES                  AGE   VERSION        INTERNAL-IP
# k3s-1  Ready    control-plane,master   5m    v1.32.x        192.168.1.160
# k3s-2  Ready    control-plane,master   3m    v1.32.x        192.168.1.161
# k3s-3  Ready    control-plane,master   3m    v1.32.x        192.168.1.162
```

## Fase 6 — Verifica post-deploy

### Stato del cluster K8s

```bash
# Tutti i nodi devono essere Ready
kubectl get nodes -o wide
# NAME           STATUS   ROLES           AGE   VERSION   INTERNAL-IP
# k8s-master-1   Ready    control-plane   5m    1.35.4   192.168.1.210
# k8s-worker-1   Ready    <none>          3m    1.35.4   192.168.1.220
# k8s-worker-2   Ready    <none>          3m    1.35.4   192.168.1.221

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

### Verifica cluster K3S

Se hai deployato K3S:

```bash
# Stato nodi
kubectl --kubeconfig ~/.kube/k3s-config get nodes -o wide

# Componenti di sistema
kubectl --kubeconfig ~/.kube/k3s-config get pods -A

# Deploy test
kubectl --kubeconfig ~/.kube/k3s-config create deployment nginx --image=nginx
kubectl --kubeconfig ~/.kube/k3s-config wait --for=condition=available deployment/nginx --timeout=60s
kubectl --kubeconfig ~/.kube/k3s-config get pods -o wide

# Cleanup
kubectl --kubeconfig ~/.kube/k3s-config delete deployment nginx
```

---

## Struttura del repository

```
home-lab/
│
├── setup-bastion.sh                    # Fase 0: installa tooling sul bastion
├── init-project.sh                     # Fase 1: inizializzazione progetto
├── verify-init.sh                      #   verifica configurazione
├── ansible/playbooks/create_proxmox_user.yml  #   playbook creazione utente API
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
├── terraform/                          # Fase 3a: VM del cluster K8s
│   ├── main.tf                         #   provider bpg/proxmox
│   ├── variables.tf                    #   tutte le variabili
│   ├── k8s-cluster.tf                  #   topologia cluster + inventory
│   ├── configure-cluster.sh            #   wizard interattivo topologia
│   ├── outputs.tf                      #   IP, comandi SSH, path inventory
│   ├── terraform.tfvars.example        #   esempio valori
│   ├── terraform.auto.tfvars*          #   credenziali + rete (da init-project.sh)
│   ├── terraform.tfvars                #   topologia cluster (tracciato)
│   ├── templates/
│   │   └── kubespray-inventory.tftpl   #   template per hosts.ini
│   ├── generated/                      #   (gitignored) output post-apply
│   └── modules/proxmox-vm/             #   modulo VM riusabile
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
│
├── terraform-k3s/                      # Fase 3b: VM del cluster K3S (opzionale)
│   ├── providers.tf                    #   provider Proxmox
│   ├── variables.tf                    #   variabili rete, VM, risorse
│   ├── main.tf                         #   3 VM k3s-{1..3} + inventory
│   ├── terraform.tfvars*               #   topologia K3S (generato da init-project.sh)
│   └── templates/
│       └── k3s-inventory.tftpl         #   template per k3s/inventory.ini
│
├── k3s/                                # Fase 5: deploy K3S (opzionale)
│   ├── deploy.sh                       #   install (single-node) / join (HA) / reset
│   └── inventory.ini                   #   generato da terraform-k3s
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
    ├── terraform-k8s-cluster.md        #   dettagli Terraform K8s
    ├── terraform-k3s-cluster.md        #   dettagli Terraform K3S
    ├── kubespray-deploy.md             #   dettagli Kubespray
    ├── cluster-configuration.md        #   topologia e addon
    └── proxmox-api-user.md             #   dettagli utente API
```

---

## Riferimenti ai doc di dettaglio

| Documento | Contenuto |
|-----------|-----------|
| [packer-ubuntu-base.md](packer-ubuntu-base.md) | Funzionamento autoinstall Ubuntu, boot_command GRUB, cleanup template, troubleshooting |
| [terraform-k8s-cluster.md](terraform-k8s-cluster.md) | Provider bpg/proxmox, for_each, cloud-init, scalabilità cluster K8s, troubleshooting |
| [terraform-k3s-cluster.md](terraform-k3s-cluster.md) | Provisioning VM K3S: topologia, variabili, inventory, integrazione con deploy.sh |
| [kubespray-deploy.md](kubespray-deploy.md) | group_vars, Calico IPIP, venv, gestione nodi, troubleshooting |
| [proxmox-api-user.md](proxmox-api-user.md) | Creazione utente API, Ansible Vault, permessi token |
| [init-project.md](init-project.md) | Inizializzazione automatica del progetto, token, Vault |
| [cluster-configuration.md](cluster-configuration.md) | Configurazione cluster, topologia, addon |
| [packer-multiple-distributions.md](packer-multiple-distributions.md) | Build multi-distribuzione (Rocky, Debian, Ubuntu) |
| `k3s/deploy.sh` | Deploy K3S: install (single-node), join (HA), reset |

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

# 3. Topologia cluster + VM Terraform K8s
cd ../terraform
terraform init && terraform apply -parallelism=2

# 4. Cluster Kubernetes (deploy.sh copia inventory automaticamente)
cd ../kubespray && ./deploy.sh

# 5. Verifica cluster K8s
kubectl get nodes

# 6. (Opzionale) VM K3S
cd ../terraform-k3s && terraform init && terraform apply -parallelism=2

# 7. (Opzionale) Deploy K3S (due fasi)
cd ../k3s && ./deploy.sh install && ./deploy.sh join

# 8. (Opzionale) Verifica cluster K3S
kubectl --kubeconfig ~/.kube/k3s-config get nodes
```

### Operazioni ricorrenti

```bash
# Aggiungere un worker
# → terraform.tfvars: worker_count = 3
cd terraform && terraform init && terraform apply -parallelism=2
cd ../kubespray && EXTRA_ARGS="--limit k8s-worker-3" ./deploy.sh

# Aggiornare Kubernetes
# → group_vars/all/all.yml: kube_version: 1.36.0
cd kubespray && ./deploy.sh upgrade

# Rimuovere un worker
kubectl drain k8s-worker-2 --ignore-daemonsets --delete-emptydir-data
kubectl delete node k8s-worker-2
cd kubespray && ./deploy.sh remove-node k8s-worker-2
# → terraform.tfvars: worker_count = 1
cd ../terraform && terraform init && terraform apply -parallelism=2

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
