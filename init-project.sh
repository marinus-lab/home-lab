#!/usr/bin/env bash
# Inizializzazione progetto homelab — setup credenziali e configurazione
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT_PASS_FILE="$HOME/.vault_pass"

# ── Colori ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[init]${NC} $*"; }
ok()    { echo -e "${GREEN}[init]${NC} ✅ $*"; }
warn()  { echo -e "${YELLOW}[init]${NC} ⚠️  $*"; }
error() { echo -e "${RED}[init]${NC} ❌ $*" >&2; exit 1; }

# ── Verifica prerequisiti ─────────────────────────────────────────────────────
info "Verifica prerequisiti..."
command -v curl >/dev/null || error "curl non trovato"
command -v ansible-vault >/dev/null || error "ansible-vault non trovato"
command -v python3 >/dev/null || error "python3 non trovato (richiesto per parsing JSON storage Proxmox)"
[ -f "$SCRIPT_DIR/requirements.yml" ] || error "requirements.yml non trovato"
ok "Prerequisiti OK"

# ── Input utente ──────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  INIZIALIZZAZIONE HOMELAB KUBERNETES"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── PROXMOX ────────────────────────────────────────────────────────────────────
echo "🔌 CREDENZIALI PROXMOX"
echo ""

# IP/hostname Proxmox
while true; do
  read -rp "IP/hostname Proxmox (es. 192.168.1.10): " PROXMOX_HOST
  echo ""

  if [ -z "$PROXMOX_HOST" ]; then
    warn "IP/hostname Proxmox richiesto"
    continue
  fi

  ok "Proxmox host: $PROXMOX_HOST"
  break
done

# Password root Proxmox
while true; do
  read -rsp "Password utente root@pam di Proxmox: " PROXMOX_ROOT_PW
  echo ""

  if [ -z "$PROXMOX_ROOT_PW" ]; then
    warn "Password Proxmox richiesta"
    echo ""
    continue
  fi

  ok "Password Proxmox accettata"
  break
done

# ── UTENTE AUTOMATION ──────────────────────────────────────────────────────────
echo ""
echo "👤 UTENTE AUTOMATION"
echo ""
read -rp "Nome utente automation (default: automation): " API_USERNAME
API_USERNAME="${API_USERNAME:-automation}"

# ── PASSWORD API USER ──────────────────────────────────────────────────────────
echo ""
echo "🔐 PASSWORD UTENTE AUTOMATION"
echo ""
# Leggi password API finché non è valida (min 8 caratteri)
while true; do
  read -rsp "Password per utente $API_USERNAME (min 8 caratteri): " API_PASSWORD
  echo ""

  if [ -z "$API_PASSWORD" ]; then
    warn "Password richiesta"
    echo ""
    continue
  fi

  if [ ${#API_PASSWORD} -lt 8 ]; then
    warn "Password troppo corta (${#API_PASSWORD} caratteri) — richiesti almeno 8 caratteri"
    echo ""
    continue
  fi

  ok "Password accettata (${#API_PASSWORD} caratteri)"
  break
done

# ── RETE KUBERNETES ───────────────────────────────────────────────────────────
echo ""
echo "🌐 RETE KUBERNETES"
echo ""

# Subnet Kubernetes
while true; do
  read -rp "Subnet Kubernetes (es. 192.168.0.0/24): " K8S_SUBNET
  echo ""

  if [ -z "$K8S_SUBNET" ]; then
    warn "Subnet Kubernetes richiesta"
    continue
  fi

  if ! echo "$K8S_SUBNET" | grep -qE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$'; then
    warn "Formato subnet non valido (usa CIDR, es. 192.168.0.0/24)"
    echo ""
    continue
  fi

  ok "Subnet Kubernetes: $K8S_SUBNET"
  break
done

# Gateway Kubernetes
while true; do
  echo ""
  read -rp "Gateway Kubernetes (es. 192.168.0.1): " K8S_GATEWAY
  echo ""

  if [ -z "$K8S_GATEWAY" ]; then
    warn "Gateway Kubernetes richiesto"
    continue
  fi

  if ! echo "$K8S_GATEWAY" | grep -qE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'; then
    warn "Formato gateway non valido (usa formato IP, es. 192.168.0.1)"
    echo ""
    continue
  fi

  ok "Gateway Kubernetes: $K8S_GATEWAY"
  break
done

# ── Bridge di rete Proxmox ─────────────────────────────────────────────────────
echo ""
read -rp "Bridge di rete Proxmox per VM (default: vmbr0): " PROXMOX_BRIDGE
PROXMOX_BRIDGE="${PROXMOX_BRIDGE:-vmbr0}"
echo ""
ok "Bridge di rete: $PROXMOX_BRIDGE"

# Ultimo ottetto IP primo master
while true; do
  echo ""
  read -rp "Ultimo ottetto IP primo master (es. 210): " MASTER_IP_OCTET
  echo ""

  if [ -z "$MASTER_IP_OCTET" ]; then
    warn "Ultimo ottetto master richiesto"
    continue
  fi

  if ! echo "$MASTER_IP_OCTET" | grep -qE '^[0-9]{1,3}$' || [ "$MASTER_IP_OCTET" -lt 0 ] || [ "$MASTER_IP_OCTET" -gt 253 ]; then
    warn "Ottetto non valido (deve essere un numero tra 0 e 253)"
    echo ""
    continue
  fi

  ok "IP primo master: ultimo ottetto $MASTER_IP_OCTET"
  break
done

# Ultimo ottetto IP primo worker
while true; do
  echo ""
  read -rp "Ultimo ottetto IP primo worker (es. 220): " WORKER_IP_OCTET
  echo ""

  if [ -z "$WORKER_IP_OCTET" ]; then
    warn "Ultimo ottetto worker richiesto"
    continue
  fi

  if ! echo "$WORKER_IP_OCTET" | grep -qE '^[0-9]{1,3}$' || [ "$WORKER_IP_OCTET" -lt 0 ] || [ "$WORKER_IP_OCTET" -gt 253 ]; then
    warn "Ottetto non valido (deve essere un numero tra 0 e 253)"
    echo ""
    continue
  fi

  # Verifica che worker IP non sia troppo vicino a master IP
  if [ "$WORKER_IP_OCTET" -le "$((MASTER_IP_OCTET + 2))" ]; then
    warn "Ultimo ottetto worker deve essere > $((MASTER_IP_OCTET + 2)) per evitare conflitti con master"
    echo ""
    continue
  fi

  ok "IP primo worker: ultimo ottetto $WORKER_IP_OCTET"
  break
done

ok "Rete Kubernetes configurata"

# ── KUBERNETES SETUP ──────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ☸️  CONFIGURAZIONE KUBERNETES"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── Selettore versione Kubespray ─────────────────────────────────────────
info "Recupero release Kubespray da GitHub..."
KUBESPRAY_RELEASES=$(curl -s "https://api.github.com/repos/kubernetes-sigs/kubespray/releases?per_page=10" 2>/dev/null || echo "[]")

# Parsing rilasci stabili (non draft, non prerelease)
KUBESPRAY_JSON=$(echo "$KUBESPRAY_RELEASES" | python3 -c "
import json, sys
data = json.load(sys.stdin)
releases = []
for r in data:
    if r.get('draft') or r.get('prerelease'):
        continue
    releases.append({
        'tag': r.get('tag_name',''),
        'date': r.get('published_at','')[:10],
    })
# Ordina per data decrescente
releases.sort(key=lambda x: x['date'], reverse=True)
for r in releases[:5]:
    print(f\"{r['tag']}|{r['date']}\")
" 2>/dev/null)

# Leggi in array
mapfile -t KUBESPRAY_TAGS < <(echo "$KUBESPRAY_JSON" | cut -d'|' -f1)
mapfile -t KUBESPRAY_DATES < <(echo "$KUBESPRAY_JSON" | cut -d'|' -f2)

if [ ${#KUBESPRAY_TAGS[@]} -lt 1 ]; then
  warn "Impossibile recuperare release Kubespray — uso default"
  KUBESPRAY_TAGS=("v2.31.0" "v2.30.0" "v2.29.1")
  KUBESPRAY_DATES=("2026-04-25" "2026-01-29" "2025-12-11")
fi

# Per ogni tag, recupera la max K8s supportata
KUBESPRAY_MAX_K8S=()
for tag in "${KUBESPRAY_TAGS[@]}"; do
  # Prova nuovo path (v2.30+)
  k8s_ver=$(curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kubespray/$tag/roles/kubespray_defaults/vars/main/checksums.yml" 2>/dev/null | \
    awk '/^kubelet_checksums:/{f=1} f && /^  amd64:/{a=1; next} a && /^    [0-9]/{print; exit}' | \
    grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
  # Fallback path (v2.26.x)
  if [ -z "$k8s_ver" ]; then
    k8s_ver=$(curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kubespray/$tag/roles/kubespray-defaults/defaults/main/checksums.yml" 2>/dev/null | \
      awk '/^kubelet_checksums:/{f=1} f && /^  amd64:/{a=1; next} a && /^    [0-9]/{print; exit}' | \
      grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
  fi
  [ -z "$k8s_ver" ] && k8s_ver="N/D"
  KUBESPRAY_MAX_K8S+=("$k8s_ver")
done

# Mostra menu limitato a 3 entry
echo ""
echo "Seleziona versione Kubespray:"
echo ""
echo "  #  Tag          Pubblicato    K8s max"
echo "  ─────────────────────────────────────"
MAX_SHOW=$(( ${#KUBESPRAY_TAGS[@]} < 3 ? ${#KUBESPRAY_TAGS[@]} : 3 ))
for i in $(seq 0 $((MAX_SHOW - 1))); do
  printf "  %d)  %-12s  %-12s  %s\n" $((i+1)) "${KUBESPRAY_TAGS[$i]}" "${KUBESPRAY_DATES[$i]}" "${KUBESPRAY_MAX_K8S[$i]}"
done
echo ""

while true; do
  read -rp "Scelta (1-$MAX_SHOW): " K8S_SEL
  if echo "$K8S_SEL" | grep -qE '^[0-9]+$' && [ "$K8S_SEL" -ge 1 ] && [ "$K8S_SEL" -le "$MAX_SHOW" ]; then
    KUBESPRAY_VERSION="${KUBESPRAY_TAGS[$((K8S_SEL-1))]}"
    DEFAULT_KUBE_VERSION="${KUBESPRAY_MAX_K8S[$((K8S_SEL-1))]}"
    ok "Kubespray selezionato: $KUBESPRAY_VERSION"
    break
  fi
  warn "Scelta non valida (1-$MAX_SHOW)"
done

# ── Versione Kubernetes ──────────────────────────────────────────────────
echo ""
echo "Versione Kubernetes supportata: $DEFAULT_KUBE_VERSION"
while true; do
  read -rp "Versione Kubernetes (default: $DEFAULT_KUBE_VERSION, Enter per confermare): " KUBE_VERSION
  KUBE_VERSION="${KUBE_VERSION:-$DEFAULT_KUBE_VERSION}"
  if echo "$KUBE_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    ok "Kubernetes $KUBE_VERSION"
    break
  fi
  warn "Formato non valido (usa X.Y.Z, es. $DEFAULT_KUBE_VERSION)"
done

# ── Nome cluster ─────────────────────────────────────────────────────────
echo ""
while true; do
  read -rp "Nome cluster (default: homelab): " CLUSTER_NAME
  CLUSTER_NAME="${CLUSTER_NAME:-homelab}"
  if echo "$CLUSTER_NAME" | grep -qE '^[a-z0-9]([a-z0-9-]*[a-z0-9])?$'; then
    ok "Nome cluster: $CLUSTER_NAME"
    break
  fi
  warn "Solo lettere minuscole, numeri e trattini (es. homelab, my-cluster)"
done

# ── Genera kubespray inventory group_vars all.yml ─────────────────────────
KUBESPRAY_ALL_YML="$SCRIPT_DIR/kubespray/inventory/homelab/group_vars/all/all.yml"
if [ -f "$KUBESPRAY_ALL_YML" ]; then
  cp "$KUBESPRAY_ALL_YML" "$KUBESPRAY_ALL_YML.bak"
  warn "Backup creato: $KUBESPRAY_ALL_YML.bak"
fi
mkdir -p "$(dirname "$KUBESPRAY_ALL_YML")"

cat > "$KUBESPRAY_ALL_YML" << K8S_EOF
---
# ── Cluster ────────────────────────────────────────────────────────────────────
cluster_name: $CLUSTER_NAME

# ── Versione Kubernetes ────────────────────────────────────────────────────────
# Verificare la compatibilità con la versione Kubespray in uso:
# https://github.com/kubernetes-sigs/kubespray#supported-components
kube_version: $KUBE_VERSION

# ── Versione Kubespray ─────────────────────────────────────────────────────────
# Tag release da usare per il clone. Vuoto = branch main.
kubespray_version: $KUBESPRAY_VERSION

# ── DNS upstream ───────────────────────────────────────────────────────────────
upstream_dns_servers:
  - 1.1.1.1
  - 8.8.8.8

# ── Ottimizzazione download binari ────────────────────────────────────────────
download_run_once: true
download_localhost: false

# ── NTP ────────────────────────────────────────────────────────────────────────
ntp_enabled: true
ntp_manage_config: true
ntp_servers:
  - 0.it.pool.ntp.org
  - 1.it.pool.ntp.org
  - 2.it.pool.ntp.org

# ── SSH ────────────────────────────────────────────────────────────────────────
ansible_user: ubuntu
ansible_become: true
K8S_EOF

ok "$KUBESPRAY_ALL_YML generato (cluster: $CLUSTER_NAME, K8s: $KUBE_VERSION, Kubespray: $KUBESPRAY_VERSION)"

echo ""
ok "Configurazione Kubernetes completata"

# NOTA: Gli storage pool Proxmox vengono rilevati dinamicamente dopo aver
# ottenuto il ticket di sessione (vedi sezione "RILEVAMENTO STORAGE PROXMOX")

# ── VAULT PASSWORD ────────────────────────────────────────────────────────────
echo ""
echo "🔐 PASSWORD VAULT"
echo ""

while true; do
  read -rsp "Password per il Vault (proteggere bene!): " VAULT_PASSWORD
  echo ""

  if [ -z "$VAULT_PASSWORD" ]; then
    warn "Password Vault richiesta"
    echo ""
    continue
  fi

  ok "Password Vault accettata"
  break
done

# ── Salva password Vault ──────────────────────────────────────────────────────
info "Salvataggio password Vault in $VAULT_PASS_FILE"
echo "$VAULT_PASSWORD" > "$VAULT_PASS_FILE"
chmod 600 "$VAULT_PASS_FILE"
ok "Password Vault salvata"

# ── Crea group_vars/all.yml con credenziali cifrate ──────────────────────────
info "Cifratura credenziali Ansible Vault..."

if [ -f "$SCRIPT_DIR/group_vars/all.yml" ]; then
  cp "$SCRIPT_DIR/group_vars/all.yml" "$SCRIPT_DIR/group_vars/all.yml.bak"
  warn "Backup creato: group_vars/all.yml.bak"
fi

# Genera il file YAML con variabili cifrate
# Usa encrypt_string per ogni variabile e formatta il YAML manualmente
PROXMOX_ROOT_ENCRYPTED=$(echo "$PROXMOX_ROOT_PW" | \
  ansible-vault encrypt_string --vault-password-file "$VAULT_PASS_FILE" 2>/dev/null)

API_PASSWORD_ENCRYPTED=$(echo "$API_PASSWORD" | \
  ansible-vault encrypt_string --vault-password-file "$VAULT_PASS_FILE" 2>/dev/null)

cat > "$SCRIPT_DIR/group_vars/all.yml" << EOF
---
# Credenziali Proxmox — CIFRATE CON ANSIBLE VAULT
vault_proxmox_root_pw: $PROXMOX_ROOT_ENCRYPTED
vault_automation_user_pw: $API_PASSWORD_ENCRYPTED
EOF

ok "Credenziali cifrate in group_vars/all.yml"

# ── Genera packer/packer.pkrvars.hcl ──────────────────────────────────────────
info "Generazione packer/packer.pkrvars.hcl..."

cat > "$SCRIPT_DIR/packer/packer.pkrvars.hcl" << EOF
# Generato automaticamente da init-project.sh

# ── Credenziali Proxmox ────────────────────────────────────────────────────────
proxmox_url          = "https://$PROXMOX_HOST:8006/api2/json"
proxmox_token_id     = "$API_USERNAME@pve!packer"
proxmox_token_secret = "PLACEHOLDER_GENERATO_DA_CURL"
proxmox_node         = "PLACEHOLDER_NODO"

# ── Rete ───────────────────────────────────────────────────────────────────────
network_bridge = "$PROXMOX_BRIDGE"

# ── Storage Packer (rilevati dinamicamente da Proxmox API) ────────────────────
iso_storage_pool      = "PLACEHOLDER_ISO_POOL"
template_storage_pool = "PLACEHOLDER_TEMPLATE_POOL"
EOF

ok "packer/packer.pkrvars.hcl creato"

# ── Genera terraform/terraform.auto.tfvars (credenziali) ────────────────────────
info "Generazione terraform/terraform.auto.tfvars..."

cat > "$SCRIPT_DIR/terraform/terraform.auto.tfvars" << EOF
# CREDENZIALI E CONFIGURAZIONE RETE — Generato automaticamente da init-project.sh
# NON tracciato in git (.gitignore)

# ── Credenziali Proxmox ────────────────────────────────────────────────────────
proxmox_url          = "https://$PROXMOX_HOST:8006/api2/json"
proxmox_token_id     = "$API_USERNAME@pve!terraform"
proxmox_token_secret = "PLACEHOLDER_GENERATO_DA_CURL"
proxmox_node         = "PLACEHOLDER_NODO"

# ── Rete Kubernetes ────────────────────────────────────────────────────────────
k8s_subnet      = "$K8S_SUBNET"
k8s_gateway     = "$K8S_GATEWAY"
master_ip_start = $MASTER_IP_OCTET
worker_ip_start = $WORKER_IP_OCTET

# ── Bridge di rete Proxmox per VM ──────────────────────────────────────────────
network_bridge = "$PROXMOX_BRIDGE"

# ── Storage Proxmox (rilevati dinamicamente da Proxmox API) ───────────────────
storage_pool = "PLACEHOLDER_TEMPLATE_POOL"
EOF

ok "terraform/terraform.auto.tfvars creato (credenziali + rete Kubernetes)"

# ── Genera terraform-k3s/terraform.auto.tfvars (credenziali) ────────────────────
info "Generazione terraform-k3s/terraform.auto.tfvars..."
mkdir -p "$SCRIPT_DIR/terraform-k3s"

cat > "$SCRIPT_DIR/terraform-k3s/terraform.auto.tfvars" << EOF
# CREDENZIALI E CONFIGURAZIONE RETE — Generato automaticamente da init-project.sh

# ── Credenziali Proxmox ────────────────────────────────────────────────────────
proxmox_url          = "https://$PROXMOX_HOST:8006/api2/json"
proxmox_token_id     = "$API_USERNAME@pve!terraform"
proxmox_token_secret = "PLACEHOLDER_GENERATO_DA_CURL"
proxmox_node         = "PLACEHOLDER_NODO"

# ── Rete K3S ───────────────────────────────────────────────────────────────────
k3s_subnet       = "$K8S_SUBNET"
k3s_gateway      = "$K8S_GATEWAY"

# ── Storage Proxmox (rilevato dinamicamente) ──────────────────────────────────
storage_pool = "PLACEHOLDER_TEMPLATE_POOL"
EOF

ok "terraform-k3s/terraform.auto.tfvars creato"

# ── Genera terraform-k3s/terraform.tfvars (topologia — pubblico) ───────────────
cat > "$SCRIPT_DIR/terraform-k3s/terraform.tfvars" << EOF
# Configurazione cluster K3S — Generato da init-project.sh

# ── Rete ───────────────────────────────────────────────────────────────────────
proxmox_node    = "PLACEHOLDER_NODO"
k3s_subnet      = "$K8S_SUBNET"
k3s_gateway     = "$K8S_GATEWAY"

# ── Template Packer ─────────────────────────────────────────────────────────────
template_vm_id = 9002

# ── Topologia ───────────────────────────────────────────────────────────────────
k3s_count       = 3
k3s_vm_id_start = 44777
k3s_ip_start    = 160

# ── Risorse (stesse dei master K8s) ─────────────────────────────────────────────
k3s_cpu_cores = 4
k3s_memory    = 16384
k3s_disk_size = 0
EOF

ok "terraform-k3s/terraform.tfvars creato"

# ── Genera terraform/terraform.tfvars (topologia — pubblico) ────────────────────
info "Generazione terraform/terraform.tfvars..."

cat > "$SCRIPT_DIR/terraform/terraform.tfvars" << EOF
# Configurazione cluster Kubernetes — Generato da init-project.sh
# Credenziali Proxmox: vedi terraform.auto.tfvars

# ── Rete ────────────────────────────────────────────────────────────────────────
proxmox_node = "PLACEHOLDER_NODO"
k8s_subnet   = "$K8S_SUBNET"
k8s_gateway  = "$K8S_GATEWAY"

# ── Template Packer ─────────────────────────────────────────────────────────────
template_vm_id = 9002

# ── Nomi VM ─────────────────────────────────────────────────────────────────────
master_name_prefix = "k8s-master"
worker_name_prefix = "k8s-worker"

# ── Topologia ────────────────────────────────────────────────────────────────────
control_plane_count = 3
worker_count        = 3

# ── VM ID ───────────────────────────────────────────────────────────────────────
master_vm_id_start = 44555
worker_vm_id_start = 44666

# ── IP ──────────────────────────────────────────────────────────────────────────
master_ip_start = $MASTER_IP_OCTET
worker_ip_start = $WORKER_IP_OCTET

# ── Risorse master ──────────────────────────────────────────────────────────────
master_cpu_cores = 4
master_memory    = 16384
master_disk_size = 0

# ── Risorse worker ──────────────────────────────────────────────────────────────
worker_cpu_cores = 4
worker_memory    = 16384
worker_disk_size = 50
EOF

ok "terraform/terraform.tfvars creato (topologia cluster)"

# ── Crea l'utente API su Proxmox con curl ─────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  CREAZIONE UTENTE API SU PROXMOX"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

info "Ottenimento ticket di sessione Proxmox..."

# Ottieni il ticket di sessione (richiesto per le operazioni API)
TICKET_RESPONSE=$(curl -s -k -X POST \
  "https://$PROXMOX_HOST:8006/api2/json/access/ticket" \
  -d "username=root@pam&password=$PROXMOX_ROOT_PW" 2>/dev/null || echo '{}')

TICKET=$(echo "$TICKET_RESPONSE" | grep -oP '"ticket"\s*:\s*"\K[^"]+' | head -1)
CSRF_TOKEN=$(echo "$TICKET_RESPONSE" | grep -oP '"CSRFPreventionToken"\s*:\s*"\K[^"]+' | head -1)

if [ -z "$TICKET" ]; then
  error "Impossibile ottenere ticket di sessione. Risposta: $TICKET_RESPONSE"
fi

ok "Ticket di sessione ottenuto"

# ── Rileva il nodo Proxmox disponibile ─────────────────────────────────────────
info "Rilevamento nodo Proxmox..."

NODES_RESPONSE=$(curl -s -k -X GET \
  "https://$PROXMOX_HOST:8006/api2/json/nodes" \
  -b "PVEAuthCookie=$TICKET" \
  -H "CSRFPreventionToken: $CSRF_TOKEN" 2>/dev/null)

# Estrai lista nodi dal JSON (prova con grep per robustezza)
NODES_LIST=$(echo "$NODES_RESPONSE" | grep -oP '"node"\s*:\s*"\K[^"]+' | sort -u)

# Conta nodi
NODES_COUNT=$(echo "$NODES_LIST" | wc -l)

if [ -z "$NODES_LIST" ]; then
  error "Nessun nodo trovato in Proxmox. Risposta: $NODES_RESPONSE"
fi

if [ "$NODES_COUNT" -eq 1 ]; then
  PROXMOX_NODE=$(echo "$NODES_LIST" | head -1)
  ok "Nodo Proxmox rilevato: $PROXMOX_NODE"
else
  # Più nodi — chiedi all'utente
  warn "Trovati $NODES_COUNT nodi Proxmox:"
  echo ""
  echo "Nodi disponibili:"
  echo "$NODES_LIST" | nl
  echo ""
  read -rp "Seleziona il numero del nodo da usare: " NODE_NUM
  PROXMOX_NODE=$(echo "$NODES_LIST" | sed -n "${NODE_NUM}p")

  if [ -z "$PROXMOX_NODE" ]; then
    error "Selezione nodo non valida"
  fi
  ok "Nodo selezionato: $PROXMOX_NODE"
fi

# ── Rilevamento storage Proxmox disponibili ────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  💾 RILEVAMENTO STORAGE PROXMOX"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

info "Recupero storage disponibili sul nodo $PROXMOX_NODE..."

STORAGE_RESPONSE=$(curl -s -k -X GET \
  "https://$PROXMOX_HOST:8006/api2/json/nodes/$PROXMOX_NODE/storage" \
  -b "PVEAuthCookie=$TICKET" \
  -H "CSRFPreventionToken: $CSRF_TOKEN" 2>/dev/null || echo '{"data":[]}')

# Salva risposta per debug
echo "$STORAGE_RESPONSE" > /tmp/proxmox_storage_debug.json

# Parsing JSON: per ogni storage estraiamo storage_name|content|enabled|active
# Usiamo python3 perché il JSON è complesso e ha array nested
STORAGE_DATA=$(echo "$STORAGE_RESPONSE" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for s in data.get('data', []):
        name = s.get('storage', '')
        content = s.get('content', '')
        enabled = s.get('enabled', 1)
        active = s.get('active', 1)
        stype = s.get('type', '')
        if enabled and active and name:
            print(f'{name}|{content}|{stype}')
except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
" 2>/dev/null)

if [ -z "$STORAGE_DATA" ]; then
  error "Nessuno storage disponibile rilevato. Risposta: $STORAGE_RESPONSE"
fi

# Filtra storage che supportano ISO
ISO_STORAGES=$(echo "$STORAGE_DATA" | while IFS='|' read -r name content stype; do
  if echo "$content" | grep -q "iso"; then
    echo "$name|$stype|$content"
  fi
done)

# Filtra storage che supportano images (disk VM)
IMAGE_STORAGES=$(echo "$STORAGE_DATA" | while IFS='|' read -r name content stype; do
  if echo "$content" | grep -q "images"; then
    echo "$name|$stype|$content"
  fi
done)

if [ -z "$ISO_STORAGES" ]; then
  error "Nessuno storage abilitato per ISO trovato"
fi

if [ -z "$IMAGE_STORAGES" ]; then
  error "Nessuno storage abilitato per VM disk (images) trovato"
fi

# Selezione storage ISO
echo ""
echo "📀 Storage disponibili per ISO (download installer):"
echo ""
ISO_COUNT=$(echo "$ISO_STORAGES" | wc -l)
echo "$ISO_STORAGES" | awk -F'|' '{printf "  %d) %-15s [tipo: %-10s content: %s]\n", NR, $1, $2, $3}'
echo ""

while true; do
  read -rp "Seleziona storage per ISO (1-$ISO_COUNT): " ISO_NUM

  if ! echo "$ISO_NUM" | grep -qE '^[0-9]+$'; then
    warn "Inserisci un numero valido"
    continue
  fi

  if [ "$ISO_NUM" -lt 1 ] || [ "$ISO_NUM" -gt "$ISO_COUNT" ]; then
    warn "Numero fuori range (1-$ISO_COUNT)"
    continue
  fi

  PACKER_ISO_POOL=$(echo "$ISO_STORAGES" | sed -n "${ISO_NUM}p" | cut -d'|' -f1)
  ok "Storage ISO selezionato: $PACKER_ISO_POOL"
  break
done

# Selezione storage Template
echo ""
echo "💿 Storage disponibili per VM disk (template):"
echo ""
IMAGE_COUNT=$(echo "$IMAGE_STORAGES" | wc -l)
echo "$IMAGE_STORAGES" | awk -F'|' '{printf "  %d) %-15s [tipo: %-10s content: %s]\n", NR, $1, $2, $3}'
echo ""

while true; do
  read -rp "Seleziona storage per template VM (1-$IMAGE_COUNT): " IMG_NUM

  if ! echo "$IMG_NUM" | grep -qE '^[0-9]+$'; then
    warn "Inserisci un numero valido"
    continue
  fi

  if [ "$IMG_NUM" -lt 1 ] || [ "$IMG_NUM" -gt "$IMAGE_COUNT" ]; then
    warn "Numero fuori range (1-$IMAGE_COUNT)"
    continue
  fi

  PACKER_TEMPLATE_POOL=$(echo "$IMAGE_STORAGES" | sed -n "${IMG_NUM}p" | cut -d'|' -f1)
  ok "Storage template selezionato: $PACKER_TEMPLATE_POOL"
  break
done

ok "Storage Proxmox configurati"

info "Creazione utente $API_USERNAME@pve su $PROXMOX_HOST..."

# Crea l'utente usando il ticket (con verbose per il codice HTTP)
CURL_OUTPUT=$(curl -s -k -w "\n%{http_code}" -X POST \
  "https://$PROXMOX_HOST:8006/api2/json/access/users" \
  -b "PVEAuthCookie=$TICKET" \
  -H "CSRFPreventionToken: $CSRF_TOKEN" \
  -d "userid=$API_USERNAME@pve&password=$API_PASSWORD&comment=Automation%20user" 2>/dev/null)

CURL_RESPONSE=$(echo "$CURL_OUTPUT" | head -n -1)
HTTP_CODE=$(echo "$CURL_OUTPUT" | tail -n 1)

# Debug
echo "$CURL_RESPONSE" > /tmp/user_creation_debug.json

# Controlla il codice HTTP
if [ "$HTTP_CODE" = "200" ]; then
  ok "Utente $API_USERNAME@pve creato"
elif echo "$CURL_RESPONSE" | grep -q "already exists"; then
  warn "Utente $API_USERNAME@pve esiste già"
else
  error "Creazione utente fallita (HTTP $HTTP_CODE). Risposta: $CURL_RESPONSE"
fi

# ── Assegnazione ACL: ruolo PVEAdmin sull'intera root ─────────────────────────
info "Assegnazione ruolo PVEAdmin a $API_USERNAME@pve..."

ACL_OUTPUT=$(curl -s -k -w "\n%{http_code}" -X PUT \
  "https://$PROXMOX_HOST:8006/api2/json/access/acl" \
  -b "PVEAuthCookie=$TICKET" \
  -H "CSRFPreventionToken: $CSRF_TOKEN" \
  -d "path=/&users=$API_USERNAME@pve&roles=PVEAdmin&propagate=1" 2>/dev/null)

ACL_HTTP=$(echo "$ACL_OUTPUT" | tail -n 1)

if [ "$ACL_HTTP" = "200" ]; then
  ok "Ruolo PVEAdmin assegnato a $API_USERNAME@pve su path '/'"
else
  ACL_BODY=$(echo "$ACL_OUTPUT" | head -n -1)
  warn "Assegnazione ACL fallita (HTTP $ACL_HTTP): $ACL_BODY"
fi

# Crea il token packer
info "Generazione token API per Packer..."

# Prova a creare il token (potrebbe già esistere)
# privsep=0 -> il token eredita TUTTI i permessi dell'utente
TOKEN_RESPONSE=$(curl -s -k -w "\n%{http_code}" -X POST \
  "https://$PROXMOX_HOST:8006/api2/json/access/users/$API_USERNAME@pve/token/packer" \
  -b "PVEAuthCookie=$TICKET" \
  -H "CSRFPreventionToken: $CSRF_TOKEN" \
  -d "comment=Packer%20token&privsep=0" 2>/dev/null || echo -e '{}\n500')

TOKEN_BODY=$(echo "$TOKEN_RESPONSE" | head -n -1)
TOKEN_HTTP=$(echo "$TOKEN_RESPONSE" | tail -n 1)

if [ "$TOKEN_HTTP" = "400" ] && echo "$TOKEN_BODY" | grep -q "already exists"; then
  warn "Token packer esiste già — elimino e ricrei..."
  curl -s -k -X DELETE \
    "https://$PROXMOX_HOST:8006/api2/json/access/users/$API_USERNAME@pve/token/packer" \
    -b "PVEAuthCookie=$TICKET" \
    -H "CSRFPreventionToken: $CSRF_TOKEN" 2>/dev/null >/dev/null

  # Ricrea il token con privsep=0
  TOKEN_RESPONSE=$(curl -s -k -X POST \
    "https://$PROXMOX_HOST:8006/api2/json/access/users/$API_USERNAME@pve/token/packer" \
    -b "PVEAuthCookie=$TICKET" \
    -H "CSRFPreventionToken: $CSRF_TOKEN" \
    -d "comment=Packer%20token&privsep=0" 2>/dev/null || echo '{}')
  TOKEN_BODY="$TOKEN_RESPONSE"
fi

# Estrai il token dal JSON
TOKEN_SECRET=$(echo "$TOKEN_BODY" | grep -oP '"value"\s*:\s*"\K[^"]+' | head -1)

if [ -z "$TOKEN_SECRET" ]; then
  error "Token Packer non generato. Risposta: $TOKEN_BODY"
fi

ok "Token Packer creato"

# Crea il token terraform
info "Generazione token API per Terraform..."

# Prova a creare il token (potrebbe già esistere)
# privsep=0 -> il token eredita TUTTI i permessi dell'utente
TERRAFORM_RESPONSE=$(curl -s -k -w "\n%{http_code}" -X POST \
  "https://$PROXMOX_HOST:8006/api2/json/access/users/$API_USERNAME@pve/token/terraform" \
  -b "PVEAuthCookie=$TICKET" \
  -H "CSRFPreventionToken: $CSRF_TOKEN" \
  -d "comment=Terraform%20token&privsep=0" 2>/dev/null || echo -e '{}\n500')

TERRAFORM_BODY=$(echo "$TERRAFORM_RESPONSE" | head -n -1)
TERRAFORM_HTTP=$(echo "$TERRAFORM_RESPONSE" | tail -n 1)

if [ "$TERRAFORM_HTTP" = "400" ] && echo "$TERRAFORM_BODY" | grep -q "already exists"; then
  warn "Token terraform esiste già — elimino e ricrei..."
  curl -s -k -X DELETE \
    "https://$PROXMOX_HOST:8006/api2/json/access/users/$API_USERNAME@pve/token/terraform" \
    -b "PVEAuthCookie=$TICKET" \
    -H "CSRFPreventionToken: $CSRF_TOKEN" 2>/dev/null >/dev/null

  # Ricrea il token con privsep=0
  TERRAFORM_RESPONSE=$(curl -s -k -X POST \
    "https://$PROXMOX_HOST:8006/api2/json/access/users/$API_USERNAME@pve/token/terraform" \
    -b "PVEAuthCookie=$TICKET" \
    -H "CSRFPreventionToken: $CSRF_TOKEN" \
    -d "comment=Terraform%20token&privsep=0" 2>/dev/null || echo '{}')
  TERRAFORM_BODY="$TERRAFORM_RESPONSE"
fi

# Estrai il token dal JSON
TERRAFORM_SECRET=$(echo "$TERRAFORM_BODY" | grep -oP '"value"\s*:\s*"\K[^"]+' | head -1)

if [ -z "$TERRAFORM_SECRET" ]; then
  warn "Token Terraform non generato — usa lo stesso di Packer"
  TERRAFORM_SECRET="$TOKEN_SECRET"
else
  ok "Token Terraform creato"
fi

# ── Aggiorna i file con i token e il nodo ────────────────────────────────────
info "Aggiornamento file di configurazione con token, nodo e storage Proxmox..."

# Aggiorna placeholder in packer (sostituzione robusta, indipendente dagli spazi)
sed -i "s|\"PLACEHOLDER_GENERATO_DA_CURL\"|\"$TOKEN_SECRET\"|g" "$SCRIPT_DIR/packer/packer.pkrvars.hcl"
sed -i "s|\"PLACEHOLDER_NODO\"|\"$PROXMOX_NODE\"|g" "$SCRIPT_DIR/packer/packer.pkrvars.hcl"
sed -i "s|\"PLACEHOLDER_ISO_POOL\"|\"$PACKER_ISO_POOL\"|g" "$SCRIPT_DIR/packer/packer.pkrvars.hcl"
sed -i "s|\"PLACEHOLDER_TEMPLATE_POOL\"|\"$PACKER_TEMPLATE_POOL\"|g" "$SCRIPT_DIR/packer/packer.pkrvars.hcl"

# Aggiorna placeholder in terraform (sostituzione robusta, indipendente dagli spazi)
sed -i "s|\"PLACEHOLDER_GENERATO_DA_CURL\"|\"$TERRAFORM_SECRET\"|g" "$SCRIPT_DIR/terraform/terraform.auto.tfvars"
sed -i "s|\"PLACEHOLDER_NODO\"|\"$PROXMOX_NODE\"|g" "$SCRIPT_DIR/terraform/terraform.auto.tfvars"
sed -i "s|\"PLACEHOLDER_NODO\"|\"$PROXMOX_NODE\"|g" "$SCRIPT_DIR/terraform/terraform.tfvars"
sed -i "s|\"PLACEHOLDER_TEMPLATE_POOL\"|\"$PACKER_TEMPLATE_POOL\"|g" "$SCRIPT_DIR/terraform/terraform.auto.tfvars"

# Aggiorna placeholder in terraform-k3s
sed -i "s|\"PLACEHOLDER_GENERATO_DA_CURL\"|\"$TERRAFORM_SECRET\"|g" "$SCRIPT_DIR/terraform-k3s/terraform.auto.tfvars"
sed -i "s|\"PLACEHOLDER_NODO\"|\"$PROXMOX_NODE\"|g" "$SCRIPT_DIR/terraform-k3s/terraform.auto.tfvars"
sed -i "s|\"PLACEHOLDER_NODO\"|\"$PROXMOX_NODE\"|g" "$SCRIPT_DIR/terraform-k3s/terraform.tfvars"
sed -i "s|\"PLACEHOLDER_TEMPLATE_POOL\"|\"$PACKER_TEMPLATE_POOL\"|g" "$SCRIPT_DIR/terraform-k3s/terraform.auto.tfvars"

ok "Token, nodo e storage Proxmox inseriti nei file di configurazione"

# ── Riepilogo ─────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ INIZIALIZZAZIONE COMPLETATA"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "File creati/aggiornati:"
echo "  • group_vars/all.yml                    (credenziali Proxmox cifrate)"
echo "  • packer/packer.pkrvars.hcl             (token Packer)"
echo "  • terraform/terraform.auto.tfvars       (credenziali + rete Kubernetes)"
echo "  • terraform/terraform.tfvars            (topologia cluster - pubblico)"
echo "  • terraform-k3s/terraform.auto.tfvars   (credenziali + rete K3S)"
echo "  • terraform-k3s/terraform.tfvars        (topologia K3S - pubblico)"
echo "  • kubespray/inventory/.../all.yml       (config cluster K8s)"
echo ""
echo "Configurazione Kubernetes:"
echo "  • Subnet: $K8S_SUBNET"
echo "  • Gateway: $K8S_GATEWAY"
echo "  • Master IP: $MASTER_IP_OCTET-$((MASTER_IP_OCTET+2))"
echo "  • Worker IP: $WORKER_IP_OCTET-$((WORKER_IP_OCTET+2))"
echo "  • Cluster name: $CLUSTER_NAME"
echo "  • K8s version: $KUBE_VERSION"
echo "  • Kubespray: $KUBESPRAY_VERSION"
echo ""
echo "Configurazione rete:"
echo "  • Bridge di rete: $PROXMOX_BRIDGE"
echo ""
echo "Configurazione Packer:"
echo "  • Bridge: $PROXMOX_BRIDGE"
echo "  • Storage ISO: $PACKER_ISO_POOL"
echo "  • Storage template: $PACKER_TEMPLATE_POOL"
echo ""
echo "Credenziali Vault salvate in:"
echo "  • $VAULT_PASS_FILE                    (proteggere!)"
echo ""
echo "Prossimi passi:"
echo "  1. (Opzionale) Modifica topologia: vim terraform/terraform.tfvars"
echo "  2. cd packer && ./build.sh              (crea template VM)"
echo "  3. cd ../terraform && terraform init    (inizializza provider)"
echo "  4. terraform apply -parallelism=2       (crea VM K8s)"
echo ""
echo "  Per creare anche le VM K3S:"
echo "    5. cd ../terraform-k3s && terraform init"
echo "    6. terraform apply -parallelism=2"
echo ""
echo "  Deploy K8s:"
echo "    7. cd ../kubespray && ./deploy.sh"
echo ""
echo "  Deploy K3S:"
echo "    8. cd ../k3s && ./deploy.sh install"
echo "    9. ./deploy.sh join"
echo ""
