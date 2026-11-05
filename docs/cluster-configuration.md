# Configurazione Cluster Kubernetes

## Panoramica

Questo documento descrive la configurazione attuale del cluster Kubernetes e come personalizzarla.

## Topologia attuale

**3 Master (Control Plane) + 3 Worker**

```
┌─────────────────────────────────────────────────────────────┐
│                    Cluster Kubernetes                       │
│                                                             │
│  ┌──────────┬──────────┬──────────┐                         │
│  │ Master 1 │ Master 2 │ Master 3 │  (HA etcd + API server) │
│  └──────────┴──────────┴──────────┘                         │
│           (192.168.1.210-212)                               │
│                   │                                         │
│  ┌──────────┬──────────┬──────────┐                         │
│  │ Worker 1 │ Worker 2 │ Worker 3 │  (carichi di lavoro)    │
│  └──────────┴──────────┴──────────┘                         │
│           (192.168.1.220-222)                               │
│                                                             │
│  MetalLB: ${NET_PREFIX}.120-${NET_PREFIX}.135 (16 IP)               │
│  Dashboard: Kubernetes Dashboard UI                         │
└─────────────────────────────────────────────────────────────┘
```

## Risorse per VM

I valori di default (`variables.tf` e `terraform.tfvars` generato da `init-project.sh`):
- **Master**: 16 GB RAM, 4 CPU, disco ereditato dal template (32G di default)
- **Worker**: 16 GB RAM, 4 CPU, 50 GB disco

Modificabili in `terraform/terraform.tfvars`:
- **RAM**: 16 GB (`master_memory` / `worker_memory`)
- **CPU**: 4 core (`master_cpu_cores` / `worker_cpu_cores`)
- **Disco**: `master_disk_size = 0` (nessun resize) e `worker_disk_size = 50`

**Totale cluster**: 96 GB RAM + 24 CPU

## Configurazione Terraform

Aggiorna `terraform/terraform.tfvars` con i parametri della topologia:

```hcl
# ── Cluster topology ──────────────────────────────────────
control_plane_count = 3      # 3 master (HA)
worker_count        = 3      # 3 worker

# ── Risorse VM ────────────────────────────────────────
master_memory     = 16384    # 16 GB
master_cpu_cores  = 4
worker_memory     = 16384    # 16 GB
worker_cpu_cores  = 4
```

### Topologie alternative

Se vuoi usare una topologia diversa, modifica questi parametri:

| Configurazione | Master | Worker | Risorse | Uso |
|---|---|---|---|---|
| **Minimal** | 1 | 2 | 12GB + 6CPU | Dev/test |
| **HA** | 3 | 3 | 96GB + 24CPU | Produzione homelab |
| **Large** | 3 | 5 | 136GB + 32CPU | Carichi pesanti |

**Nota**: `control_plane_count` deve essere **1 o 3** (non sono supportati 2 master per etcd quorum).

## Configurazione Kubespray

### Addons abilitati

Nel file `kubespray/inventory/homelab/group_vars/k8s_cluster/addons.yml` (gestito da `init-project.sh`):

```yaml
# ── Kubernetes Dashboard ──────────────────────────────────
# La dashboard upstream è stata rimossa da Kubespray (v2.21+).
# Viene installata post-deploy via scripts/install-dashboard.sh
# (abilitata da init-project.sh con il flag install_dashboard: true)
# install_dashboard: true
# Accesso: kubectl port-forward -n kubernetes-dashboard svc/kubernetes-dashboard 8443:443

# ── MetalLB ────────────────────────────────────────────────
metallb_enabled: true
metallb_config:
  address_pools:
    primary:
      ip_range:
        # Configurato da init-project.sh in base alla subnet (es. 192.168.1.120-192.168.1.135)
        - ${NET_PREFIX}.120-${NET_PREFIX}.135
      auto_assign: true
      avoid_buggy_ips: true
  layer2:
    - primary

# ── Metrics Server ─────────────────────────────────────────
metrics_server_enabled: true
# Per: kubectl top nodes, HorizontalPodAutoscaler

# ── Helm ───────────────────────────────────────────────────
helm_enabled: true
```

### Accedere al cluster

**Kubernetes Dashboard (dopo deployment):**
```bash
# Port-forward al servizio (se non ha LoadBalancer)
kubectl port-forward -n kubernetes-dashboard svc/kubernetes-dashboard 8443:443

# Visitare: https://localhost:8443
```

**Monitoraggio risorse:**
```bash
# Top nodes
kubectl top nodes

# Top pods in tutti i namespace
kubectl top pods --all-namespaces

# Dettagli cluster
kubectl cluster-info
```

## MetalLB

### Cos'è MetalLB?

MetalLB è un load balancer software per homelab/on-premise Kubernetes. Permette ai servizi `LoadBalancer` di ottenere un IP pubblico (invece di restare in `Pending`).

### Range IP

**Range configurato**: ${NET_PREFIX}.120-${NET_PREFIX}.135 (16 IP)  *(valore di default: 192.168.1.120-192.168.1.135, sovrascrivibile in init-project.sh)*

- **Protocollo**: Layer2 (ARP, funziona sulla stessa subnet)
- **Uso**: Automatico per servizi di tipo `LoadBalancer`

### Esempio: creare un servizio LoadBalancer

```yaml
apiVersion: v1
kind: Service
metadata:
  name: mio-servizio
spec:
  type: LoadBalancer
  selector:
    app: mia-app
  ports:
    - protocol: TCP
      port: 80
      targetPort: 8080
```

MetalLB assegnerà automaticamente un IP da ${NET_PREFIX}.120-${NET_PREFIX}.135:

```bash
$ kubectl get svc
NAME           TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)        AGE
mio-servizio   LoadBalancer   10.233.x.x      192.168.1.120    80:32xxx/TCP   1m
```

## Storage

### Longhorn Storage (Consigliato)

Longhorn è un sistema di storage distribuito ottimizzato per Kubernetes. Fornisce:
- Storage condiviso su tutti i nodi
- Replica automatica (default: 2 copie)
- Snapshot e backup integrati
- Dashboard web per monitoraggio

**Installazione:**
```bash
# Dal root del repository
./kubespray/scripts/longhorn-install.sh

# Oppure manuale
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.7.1/deploy/longhorn.yaml
```

**Configurazione dischi:**
1. Accedi alla dashboard: http://[IP-METALLB]:80
2. Vai su Storage → Disk → Add Disk
3. Configura su ogni nodo Kubernetes
4. Usa StorageClass: `longhorn-local`

**PVC con Longhorn:**
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mio-pvc
spec:
  storageClassName: longhorn-local
  accessModes: [ "ReadWriteOnce" ]
  resources:
    requests:
      storage: 10Gi
```

## Prossimi step

1. **Aggiorna terraform/terraform.tfvars** con i parametri della topologia
2. **Esegui Terraform**: `cd terraform && terraform init && terraform apply -parallelism=1`
3. **Esegui Kubespray**: `./deploy.sh`
4. **Installa Longhorn**: `./kubespray/scripts/longhorn-install.sh`
5. **Configura dischi** nella dashboard Longhorn
6. **Accedi al cluster**:
   - Dashboard: `kubectl port-forward -n kubernetes-dashboard svc/kubernetes-dashboard 8443:443`
   - Longhorn: http://[IP-METALLB]:80

## Documentazione completa

- Terraform: `docs/terraform-k8s-cluster.md` (setup credenziali)
- Kubespray: `docs/kubespray-deploy.md` (deployment K8s)
- MetalLB: https://metallb.universe.tf/
- Kubernetes Dashboard: https://kubernetes.io/docs/tasks/access-application-cluster/web-ui-dashboard/
- Longhorn: https://longhorn.io/
