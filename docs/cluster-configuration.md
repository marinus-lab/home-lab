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
│  MetalLB: 192.168.1.120-192.168.1.135 (16 IP)               │
│  Dashboard: Kubernetes Dashboard UI                         │
└─────────────────────────────────────────────────────────────┘
```

## Risorse per VM

I valori predefiniti di Terraform (`variables.tf`) usano risorse contenute:
- **Master**: 2 GB RAM, 2 CPU, 30 GB disco
- **Worker**: 4 GB RAM, 4 CPU, 50 GB disco

Dopo aver eseguito `init-project.sh` (o `configure-cluster.sh`), le risorse vengono sovrascritte con valori più generosi:
- **RAM**: 16 GB
- **CPU**: 4 core
- **Disco**: preserva la dimensione del template (default 32G) per i master; 50 GB per i worker

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

Nel file `kubespray/inventory/homelab/group_vars/k8s_cluster/addons.yml`:

```yaml
# ── Kubernetes Dashboard ──────────────────────────────────
dashboard_enabled: true
# Accesso: kubectl port-forward -n kube-system svc/kubernetes-dashboard 8443:443

# ── MetalLB ────────────────────────────────────────────────
metallb_enabled: true
metallb_config:
  address_pools:
    primary:
      ip_range:
        - 192.168.1.120-192.168.1.135
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
kubectl port-forward -n kube-system svc/kubernetes-dashboard 8443:443

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

**Range configurato**: 192.168.1.120-192.168.1.135 (16 IP)

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

MetalLB assegnerà automaticamente un IP da 192.168.1.120-192.168.1.135:

```bash
$ kubectl get svc
NAME           TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)        AGE
mio-servizio   LoadBalancer   10.233.x.x      192.168.1.120    80:32xxx/TCP   1m
```

## Prossimi step

1. **Aggiorna terraform/terraform.tfvars** con i parametri della topologia
2. **Esegui Terraform**: `cd terraform && terraform init && terraform apply -parallelism=2`
3. **Esegui Kubespray**: `./deploy.sh`
4. **Accedi al cluster**:
   - Dashboard: `kubectl port-forward -n kube-system svc/kubernetes-dashboard 8443:443`
   - Test MetalLB: crea un servizio LoadBalancer

## Documentazione completa

- Terraform: `docs/terraform-k8s-cluster.md` (setup credenziali)
- Kubespray: `docs/kubespray-deploy.md` (deployment K8s)
- MetalLB: https://metallb.universe.tf/
- Kubernetes Dashboard: https://kubernetes.io/docs/tasks/access-application-cluster/web-ui-dashboard/
