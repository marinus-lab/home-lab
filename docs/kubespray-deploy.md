# Kubespray — Deploy cluster Kubernetes su Proxmox

## Indice

1. [Panoramica](#panoramica)
2. [Prerequisiti](#prerequisiti)
3. [Struttura dei file](#struttura-dei-file)
4. [Flusso completo end-to-end](#flusso-completo-end-to-end)
5. [File di configurazione](#file-di-configurazione)
   - [hosts.ini](#hostsini)
   - [group_vars/all/all.yml](#group_varsallallyml)
   - [group_vars/all/containerd.yml](#group_varsallcontainerdyml)
   - [group_vars/k8s_cluster/k8s-cluster.yml](#group_varsk8s_clusterk8s-clusteryml)
   - [group_vars/k8s_cluster/k8s-net-plugin.yml](#group_varsk8s_clusterk8s-net-pluginyml)
   - [group_vars/k8s_cluster/addons.yml](#group_varsk8s_clusteraddonsyml)
6. [deploy.sh](#deploysh)
7. [Come funziona il venv Kubespray](#come-funziona-il-venv-kubespray)
8. [Scelte di configurazione](#scelte-di-configurazione)
9. [Utilizzo](#utilizzo)
10. [Gestione del cluster post-deploy](#gestione-del-cluster-post-deploy)
11. [Troubleshooting](#troubleshooting)

---

## Panoramica

Kubespray è una collezione di playbook Ansible che installa e configura un cluster Kubernetes production-grade su VM esistenti. In questo progetto:

- Le VM sono create da **Terraform** (clonate dal template Packer)
- L'**inventory** (`hosts.ini`) è generato automaticamente da Terraform
- Il **deploy** è eseguito da `deploy.sh` che gestisce clone del repo, venv e playbook

Il bastion funge da **control node Ansible**: si connette via SSH alle VM con la chiave generata da `setup-bastion.sh` e installa K8s su tutti i nodi in parallelo.

```
Bastion (control node Ansible)
    │
    ├── SSH → k8s-master-1  (192.168.1.210)   installa: etcd, kube-apiserver,
    │                                          kube-scheduler, kube-controller-manager,
    │                                          kubelet, calico
    │
    ├── SSH → k8s-worker-1  (192.168.1.220)   installa: kubelet, kube-proxy,
    └── SSH → k8s-worker-2  (192.168.1.221)   containerd, calico node
```

---

## Prerequisiti

| Requisito | Come verificare | Come ottenere |
|-----------|-----------------|---------------|
| VM Proxmox attive | `terraform output all_nodes` | `cd terraform && terraform init && terraform apply -parallelism=2` |
| Inventory aggiornato | `cat kubespray/inventory/homelab/hosts.ini` | `cp terraform/generated/kubespray-inventory.ini kubespray/inventory/homelab/hosts.ini` |
| SSH key sul bastion | `ls ~/.ssh/id_rsa.pub` | Generata da `setup-bastion.sh` |
| SSH key nelle VM | `ssh ubuntu@<IP>` | Iniettata da Terraform via cloud-init |
| Venv Python | `ls ~/kubespray-env/bin/activate` | Installato da `setup-bastion.sh` |

---

## Struttura dei file

```
kubespray/
├── deploy.sh                            # Script di deploy/gestione cluster
├── ansible.cfg                          # Config Ansible per runs manuali
└── inventory/
    └── homelab/
        ├── hosts.ini                    # Inventory nodi (generato da Terraform)
        └── group_vars/
            ├── all/
            │   ├── all.yml              # Config generale: versione K8s, NTP, DNS
            │   └── containerd.yml       # Runtime container
            └── k8s_cluster/
                ├── k8s-cluster.yml      # Config cluster: CIDR, proxy mode, cert
                ├── k8s-net-plugin.yml   # Plugin rete: Calico IPIP
                └── addons.yml           # Addon: Helm, Metrics Server, MetalLB, ...
```

---

## Flusso completo end-to-end

```
1. init-project.sh
   ├── Prompt interattivo: Proxmox creds, rete, storage
   ├── Crea ~/kubespray-env (venv con dipendenze Ansible/Kubespray)
   ├── Crea token API Proxmox per Packer e Terraform
   ├── Prompt: scegli Kubespray version, K8s version, cluster name
   └── Genera kubespray/inventory/homelab/group_vars/all/all.yml

2. packer/build.sh
   └── Costruisce template Ubuntu 22.04 (VMID 9000) su Proxmox

3. cd terraform && terraform init && terraform apply -parallelism=2
   ├── Clona template → VM k8s-master-*, k8s-worker-*
   ├── Configura cloud-init (IP statico, SSH key)
   └── Genera terraform/generated/kubespray-inventory.ini

4. cp terraform/generated/kubespray-inventory.ini \
       kubespray/inventory/homelab/hosts.ini

5. cd kubespray && ./deploy.sh
   ├── Legge kubespray_version da all.yml
   ├── Clona / checkout tag Kubespray richiesto
   ├── Applica patch automatiche (nerdctl stderr, admin.conf insecure-skip-tls-verify)
   ├── Attiva ~/kubespray-env
   └── ansible-playbook cluster.yml → installa K8s su tutti i nodi

6. kubectl get nodes     ← cluster pronto
```

---

## File di configurazione

### `hosts.ini`

Formato INI Ansible con i gruppi richiesti da Kubespray:

```ini
[kube_control_plane]    # nodi che eseguono il control plane K8s
k8s-master-1 ansible_host=192.168.1.210 ansible_user=ubuntu

[kube_node]             # nodi worker (possono includere anche i master)
k8s-worker-1 ansible_host=192.168.1.220 ansible_user=ubuntu
k8s-worker-2 ansible_host=192.168.1.221 ansible_user=ubuntu

[etcd:children]         # dove gira etcd (di default: solo control plane)
kube_control_plane

[k8s_cluster:children]  # tutti i nodi del cluster
kube_control_plane
kube_node

[calico_rr]             # Route Reflectors Calico BGP (vuoto = disabled)
```

Il file è generato da Terraform con `templatefile()` a partire da `terraform/templates/kubespray-inventory.tftpl`. Non modificarlo manualmente — verrà sovrascritto al prossimo `terraform apply`.

---

### `group_vars/all/all.yml`

**`kube_version: 1.36.0`**
La versione di Kubernetes da installare (senza prefisso `v`). Kubespray usa questo valore per scaricare i binari corretti (`kubeadm`, `kubelet`, `kubectl`). Verificare la [matrice di compatibilità Kubespray](https://github.com/kubernetes-sigs/kubespray#supported-components) prima di cambiare versione.

**`kubespray_version: v2.31.0`**
Tag di release Kubespray da clonare. Se vuoto, usa il branch `main`. Impostato automaticamente da `init-project.sh` durante l'inizializzazione del progetto. `deploy.sh` verifica la versione corrente e fa checkout del tag richiesto (chiedendo conferma se diverso).

**`download_run_once: true`**
Kubespray scarica i binari (containerd, CNI plugins, K8s binaries) una sola volta su un nodo designato e poi li distribuisce agli altri via Ansible. Riduce drasticamente il tempo di deploy su connessioni lente.

**`ntp_enabled: true`**
etcd richiede clock sincronizzati tra i nodi (tolleranza ~500ms). Senza NTP, il cluster può diventare instabile. Kubespray installa e configura `chrony` automaticamente.

---

### `group_vars/all/containerd.yml`

**`container_manager: containerd`**
Docker non è più supportato come runtime Kubernetes dalla versione 1.24 (rimosso il `dockershim`). `containerd` è il runtime standard raccomandato: leggero, conforme alla CRI spec, utilizzato in produzione da GKE, EKS, AKS.

**`containerd_registries_mirrors: []`**
Lista di mirror per registry container. Deve essere una lista (`[]`), non un dict (`{}`), perché Kubespray itera con `loop:` su questa variabile al task "Create registry directories". Lasciare vuota se non si usano mirror locali.

---

### `group_vars/k8s_cluster/k8s-cluster.yml`

**CIDR del cluster**

| Range | Valore default | Scopo |
|-------|----------------|-------|
| `kube_service_addresses` | `10.96.0.0/12` | IP per ClusterIP dei Services |
| `kube_pods_subnet` | `10.244.0.0/16` | Pool da cui allocare subnet /24 per ogni nodo |

Questi range non devono sovrapporsi con:
- La rete homelab (`192.168.1.0/24`)
- Tra loro

**`kube_proxy_mode: ipvs`**
`ipvs` (IP Virtual Server) usa tabelle hash kernel invece di catene iptables lineari. Scala meglio con molti services — per un homelab la differenza è minima, ma è la modalità raccomandata per cluster nuovi.

**`kubeconfig_localhost: true` + `kubectl_localhost: true`**
Al termine del deploy, Kubespray:
1. Scarica `~/.kube/config` sul bastion per accedere al cluster con `kubectl`
2. Installa il binario `kubectl` in `/usr/local/bin/kubectl`

**`auto_renew_certificates: true`**
I certificati K8s hanno scadenza annuale di default. Kubespray crea un servizio systemd che li rinnova automaticamente ogni primo lunedì del mese.

---

### `group_vars/k8s_cluster/k8s-net-plugin.yml`

**`calico_ipip_mode: Always`**
Calico supporta tre modalità:

| Modalità | Come funziona | Quando usarla |
|----------|---------------|---------------|
| `Always` | Tutto il traffico pod-to-pod è incapsulato in IP-in-IP | Rete L2/L3 qualsiasi — homelab ✓ |
| `CrossSubnet` | IPIP solo tra subnet diverse, nativo nella stessa | Cluster multi-subnet |
| `Never` | Nessun encapsulation, richiede routing BGP esterno | Data center con BGP |

Per un homelab su rete flat, `Always` è la scelta più semplice e compatibile.

**`calico_mtu: 1480`**
L'header IPIP aggiunge 20 byte. Con MTU Ethernet standard a 1500, il MTU del tunnel deve essere 1480 per evitare frammentazione.

---

### `group_vars/k8s_cluster/addons.yml`

Addon abilitati di default:

| Addon | Abilitato | Scopo |
|-------|-----------|-------|
| `helm_enabled` | ✅ | Package manager Kubernetes |
| `metrics_server_enabled` | ✅ | `kubectl top`, HPA |
| `dashboard_enabled` | ✅ | Dashboard web K8s |
| `ingress_nginx_enabled` | ❌ | Ingress Controller HTTP/HTTPS |
| `cert_manager_enabled` | ❌ | Certificati TLS automatici |
| `metallb_enabled` | ✅ | LoadBalancer per homelab (range: 192.168.0.120-192.168.0.135) |
| `local_volume_provisioner_enabled` | ❌ | Storage class hostPath |

---

## `deploy.sh`

Script unico per tutte le operazioni sul cluster. Gestisce automaticamente:

1. **Aggiorna inventory** — copia `terraform/generated/kubespray-inventory.ini` se più recente o mancante
2. **Verifica prerequisiti** — inventory, venv, SSH key
3. **Test SSH ping** — tenta connessione SSH a tutti i nodi prima di procedere
4. **Clone Kubespray** — se `~/kubespray` non esiste, clona il repo
5. **Patch Kubespray** — applica fix necessari al codice Kubespray (vedi sotto)
6. **Attivazione venv** — usa `~/kubespray-env` creato da `setup-bastion.sh`
7. **Esecuzione playbook** — dalla root del repo Kubespray (richiesto per trovare ruoli e ansible.cfg)

### Patch applicate al codice Kubespray (`_apply_patches`)

Il deploy script applica automaticamente alcune patch al codice Kubespray per risolvere problemi noti:

| # | File patchato | Problema | Fix |
|---|---------------|----------|-----|
| 1 | `roles/download/tasks/download_container.yml` | `nerdctl image save` scrive progress su stderr; Kubespray interpreta stderr non vuoto come fallimento (`failed_when: container_save_status.stderr`) | `failed_when: container_save_status.rc != 0` — verifica il codice di uscita invece dello stderr |
| 2 | `roles/kubernetes/control-plane/tasks/kubeadm-setup.yml` + Ansible ad-hoc pre-playbook | Tutti i comandi `kubectl --kubeconfig /etc/kubernetes/admin.conf` verso la VIP falliscono TLS (kube-proxy, calicoctl, upload-certs, ecc.) | Due vie: (a) task Ansible in `kubeadm-setup.yml` dopo `kubeadm init` (fresh-deploy); (b) `ansible kube_control_plane -m shell "sed ..."` prima del playbook (re-deploy). Il `sed` aggiunge `insecure-skip-tls-verify: true` subito dopo `certificate-authority-data:` nell'admin.conf — senza dipendere dal nome del cluster |

Le patch vengono applicate a ogni run di `deploy.sh`, sia su clone fresco (`~/kubespray` non esistente) sia su repo già esistente.

### Comandi disponibili

```bash
# Installa il cluster (prima volta)
./deploy.sh

# Aggiorna Kubernetes alla versione in k8s-cluster.yml
./deploy.sh upgrade

# Rimuove un nodo dal cluster (drain + delete)
./deploy.sh remove-node k8s-worker-2

# Rimuove completamente Kubernetes da tutti i nodi (richiede conferma)
./deploy.sh reset
```

### Variabili d'ambiente

```bash
# Path personalizzati
KUBESPRAY_DIR=~/my-kubespray ./deploy.sh

# Argomenti extra per ansible-playbook (es. verbosità, limit)
EXTRA_ARGS="-vvv" ./deploy.sh
EXTRA_ARGS="--limit k8s-worker-1" ./deploy.sh

# Inventory alternativo
INVENTORY=/path/to/other/hosts.ini ./deploy.sh
```

---

## Come funziona il venv Kubespray

`setup-bastion.sh` crea `~/kubespray-env` installando le dipendenze Python di Kubespray (principalmente `ansible-core`, `cryptography`, `netaddr`, `jinja2`). Il repo Kubespray stesso viene clonato da `deploy.sh` solo al momento del deploy in `~/kubespray`.

Questo approccio separa:
- Le **dipendenze** (nel venv, già installate) → veloci da riconfigurare
- Il **codice** Kubespray (nel repo) → aggiornabile con `git pull`

Per aggiornare Kubespray a una versione più recente:

```bash
cd ~/kubespray
git fetch --tags
git checkout v2.25.0   # tag della versione desiderata
# aggiornare anche kube_version in group_vars/all/all.yml
cd /root/home-lab/kubespray
./deploy.sh upgrade
```

---

## Scelte di configurazione

### Perché Calico e non Flannel/Cilium?

| Plugin | Pro | Contro |
|--------|-----|--------|
| **Calico** | Network policy, ben testato con Kubespray, IPIP funziona su qualsiasi infrastruttura | Configurazione leggermente più complessa |
| Flannel | Semplicissimo | No network policy, meno feature |
| Cilium | Più performante, eBPF | Richiede kernel recente, più complesso |

Per homelab con K8s standard, Calico è il punto di equilibrio ottimale.

### Perché 3 master (HA)?

Il cluster è configurato con 3 nodi control plane per l'alta disponibilità:
- etcd distribuito su 3 nodi (quorum di 2)
- kube-apiserver, kube-controller-manager, kube-scheduler attivi su tutti e 3
- Il cluster resta operativo anche se un master fallisce

Per ridurre a 1 master (risparmio risorse): cambiare `control_plane_count = 1` in `configure-cluster.sh` o `terraform.tfvars`, rieseguire `terraform init && terraform apply -parallelism=2` + `./deploy.sh upgrade`.

---

## Utilizzo

### Deploy iniziale

```bash
# 1. Avvia il deploy (20-40 minuti)
#    deploy.sh copia automaticamente l'inventory da Terraform
#    e verifica la connettività SSH prima di eseguire il playbook
./deploy.sh

# 2. Verifica il cluster
kubectl get nodes
kubectl get pods -A
```

### Verifica post-deploy

```bash
# Stato dei nodi
kubectl get nodes -o wide

# Tutti i pod (devono essere tutti Running o Completed)
kubectl get pods -A

# Versione K8s
kubectl version --short

# Metriche nodi (richiede metrics-server)
kubectl top nodes

# Test deploy applicazione
kubectl create deployment nginx --image=nginx --replicas=2
kubectl expose deployment nginx --port=80 --type=NodePort
kubectl get svc nginx
```

---

## Gestione del cluster post-deploy

### Aggiungere un worker

```bash
# 1. Aggiungere il nodo in terraform.tfvars (worker_count = 3)
cd ../terraform
terraform init
terraform apply -parallelism=2

# 2. Aggiornare l'inventory
cp generated/kubespray-inventory.ini \
   ../kubespray/inventory/homelab/hosts.ini

# 3. Aggiungere solo il nuovo nodo al cluster
cd ../kubespray
EXTRA_ARGS="--limit k8s-worker-3" ./deploy.sh
```

### Rimuovere un worker

```bash
# 1. Drain del nodo (sposta i workload)
kubectl drain k8s-worker-2 --ignore-daemonsets --delete-emptydir-data

# 2. Rimuove il nodo dal cluster K8s
kubectl delete node k8s-worker-2

# 3. Rimuove Kubernetes dalla VM
./deploy.sh remove-node k8s-worker-2

# 4. Distrugge la VM su Proxmox
cd ../terraform
# Ridurre worker_count in terraform.tfvars
terraform init
terraform apply -parallelism=2
```

### Rinnovare i certificati manualmente

```bash
# Kubespray rinnova automaticamente via systemd timer (vedi auto_renew_certificates).
# Per forzare il rinnovo:
EXTRA_ARGS="-e force_certificate_regeneration=true" \
  PLAYBOOK=upgrade-cluster.yml ./deploy.sh upgrade
```

---

## Troubleshooting

### `UNREACHABLE! => Failed to connect to the host via ssh`

La VM non è raggiungibile via SSH. Verificare:
1. La VM è avviata su Proxmox
2. cloud-init ha configurato la rete correttamente
3. La chiave SSH corrisponde

```bash
# Test di connettività
ssh -i ~/.ssh/id_rsa ubuntu@192.168.1.210

# Ping dall'inventory
ansible all -i inventory/homelab/hosts.ini -m ping \
  --private-key ~/.ssh/id_rsa
```

### `FAILED! => {"msg": "Missing sudo password"}`

Il bastion non riesce a fare `sudo` sui nodi. Verificare che il sudoers sia configurato:

```bash
# Verificare dalla VM
ssh ubuntu@192.168.1.210 "sudo id"
# Deve rispondere: uid=0(root) gid=0(root)...
```

Il file `/etc/sudoers.d/ubuntu` con `NOPASSWD:ALL` deve essere presente — è impostato dall'autoinstall Packer tramite `late-commands`.

### Il deploy si blocca su `Gathering Facts`

Sintomo: Ansible si blocca all'inizio raccogliendo i fatti di sistema.

Causa probabile: cloud-init non ha ancora finito di configurare la VM.

```bash
# Aspettare qualche minuto e riprovare
# Verificare che cloud-init sia terminato sulla VM
ssh ubuntu@<IP> "cloud-init status"
# Deve rispondere: status: done
```

### `etcdctl: command not found` dopo il deploy

etcd è installato come pod (`kube-system/etcd-k8s-master-1`), non come binario sul sistema. Per usare `etcdctl`:

```bash
kubectl exec -n kube-system etcd-k8s-master-1 -- \
  etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/ssl/etcd/ssl/ca.pem \
  --cert=/etc/ssl/etcd/ssl/member-k8s-master-1.pem \
  --key=/etc/ssl/etcd/ssl/member-k8s-master-1-key.pem \
  endpoint health
```

### I pod non comunicano tra nodi diversi

Causa: problema con Calico IPIP. Verificare lo stato di Calico:

```bash
kubectl get pods -n kube-system | grep calico

# Controlla i log del calico-node sul nodo problematico
kubectl logs -n kube-system calico-node-<hash> -c calico-node

# Verifica che IPIP sia attivo
ssh ubuntu@<IP> "ip link show tunl0"
# Deve mostrare l'interfaccia tunl0 (tunnel IPIP)
```

### `error validating data: failed to download openapi: tls: failed to verify certificate`

Compare durante i task `Registry | Apply manifests` o `Cert Manager | Apply manifests`. Il modulo Ansible `kube` esegue `kubectl apply --force` che cerca di scaricare l'OpenAPI schema dalla VIP (192.168.0.80:6443) per validare i manifest, ma la connessione TLS fallisce perché il certificato del kube-apiserver non include ancora la VIP nei SAN attendibili.

**Soluzione:** la patch `_apply_patches` in `deploy.sh` aggiunge `insecure-skip-tls-verify: true` all'admin.conf con `sed`, risolvendo tutti i TLS error verso la VIP alla radice. Il fix viene applicato automaticamente a ogni run.

### `kubectl get nodes` mostra nodi NotReady

```bash
# Controlla il kubelet sul nodo
ssh ubuntu@<IP> "sudo systemctl status kubelet"
sudo journalctl -u kubelet -n 50

# Problemi comuni:
# - swap abilitata (Kubernetes richiede swap disabilitata)
# - CNI non configurato correttamente
# - certificati scaduti
```
