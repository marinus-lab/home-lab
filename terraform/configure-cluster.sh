#!/usr/bin/env bash
# Configurazione interattiva del cluster Kubernetes
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TFVARS="$SCRIPT_DIR/terraform.tfvars"
AUTO_TFVARS="$SCRIPT_DIR/terraform.auto.tfvars"

# ── Colori ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[configure]${NC} $*"; }
ok()    { echo -e "${GREEN}[configure]${NC} $*"; }
warn()  { echo -e "${YELLOW}[configure]${NC} $*"; }
error() { echo -e "${RED}[configure]${NC} $*" >&2; exit 1; }

# ── Helper: estrae valore da file .tfvars ─────────────────────────────────────
read_var() {
  local key="$1" file="$2"
  [ -f "$file" ] || return 1
  grep -E "^\s*${key}\s*=" "$file" 2>/dev/null | head -1 \
    | sed -E "s/^\s*${key}\s*=\s*//" \
    | sed -E 's/[[:space:]]*#.*$//' \
    | sed -E 's/^"|"$//g'
}

# ── Default di lettura (con fallback) ─────────────────────────────────────────
rd() {
  local key="$1" fallback="$2"
  local val
  val=$(read_var "$key" "$TFVARS" || true)
  echo "${val:-$fallback}"
}

# ── Legge subnet/gateway da auto.tfvars (sempre prioritari) ───────────────────
K8S_SUBNET=$(read_var k8s_subnet "$AUTO_TFVARS" || echo "192.168.0.0/24")
K8S_GATEWAY=$(read_var k8s_gateway "$AUTO_TFVARS" || echo "192.168.0.100")
STORAGE_POOL=$(read_var storage_pool "$AUTO_TFVARS" || echo "local-lvm")
PROXMOX_NODE=$(read_var proxmox_node "$AUTO_TFVARS" || echo "prox-dell1")

# ── Legge valori correnti da terraform.tfvars con fallback ai default di sistema ──
CTRL_COUNT=$(rd control_plane_count 3)
WORKER_COUNT=$(rd worker_count 3)

MASTER_PREFIX=$(rd master_name_prefix "k8s-master")
WORKER_PREFIX=$(rd worker_name_prefix "k8s-worker")

MASTER_VMID=$(rd master_vm_id_start 201)
WORKER_VMID=$(rd worker_vm_id_start 211)
MASTER_IP_START=$(rd master_ip_start 150)
WORKER_IP_START=$(rd worker_ip_start 155)

MASTER_CPU=$(rd master_cpu_cores 4)
MASTER_MEM=$(rd master_memory 16384)
MASTER_DISK=$(rd master_disk_size 0)

WORKER_CPU=$(rd worker_cpu_cores 4)
WORKER_MEM=$(rd worker_memory 16384)
WORKER_DISK=$(rd worker_disk_size 50)

TEMPLATE_ID=$(rd template_vm_id 9000)

# ── Intestazione ──────────────────────────────────────────────────────────────
clear
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  CONFIGURAZIONE CLUSTER KUBERNETES"
echo "  (valori correnti tra parentesi — Invio per mantenere)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── Topologia ─────────────────────────────────────────────────────────────────
echo "┌─ TOPOLOGIA ──────────────────────────────────────────────────────────────┐"
echo ""

read -rp "  Nodi control plane [$CTRL_COUNT]: " input
CTRL_COUNT="${input:-$CTRL_COUNT}"

read -rp "  Nodi worker        [$WORKER_COUNT]: " input
WORKER_COUNT="${input:-$WORKER_COUNT}"

echo ""

# ── Nomi VM ───────────────────────────────────────────────────────────────────
echo "┌─ NOMI VM ────────────────────────────────────────────────────────────────┐"
echo ""

read -rp "  Prefisso master    [$MASTER_PREFIX]: " input
MASTER_PREFIX="${input:-$MASTER_PREFIX}"

read -rp "  Prefisso worker    [$WORKER_PREFIX]: " input
WORKER_PREFIX="${input:-$WORKER_PREFIX}"

echo ""

# ── VM ID ─────────────────────────────────────────────────────────────────────
echo "┌─ VM ID ──────────────────────────────────────────────────────────────────┐"
echo ""

read -rp "  Primo master       [$MASTER_VMID]: " input
MASTER_VMID="${input:-$MASTER_VMID}"

read -rp "  Primo worker       [$WORKER_VMID]: " input
WORKER_VMID="${input:-$WORKER_VMID}"

echo ""

# ── IP ────────────────────────────────────────────────────────────────────────
echo "┌─ IP (subnet ${K8S_SUBNET##*/} ${K8S_SUBNET%.*}.X) ────────────────────────────────────┐"
echo ""

read -rp "  Ultimo ottetto primo master     [$MASTER_IP_START]: " input
MASTER_IP_START="${input:-$MASTER_IP_START}"

read -rp "  Ultimo ottetto primo worker     [$WORKER_IP_START]: " input
WORKER_IP_START="${input:-$WORKER_IP_START}"

echo ""

# ── Template ──────────────────────────────────────────────────────────────────
echo "┌─ TEMPLATE ───────────────────────────────────────────────────────────────┐"
echo "  1) Rocky 9       (VMID 9000)"
echo "  2) Ubuntu 22.04  (VMID 9001)"
echo "  3) Ubuntu 24.04  (VMID 9002)"
echo "  4) Debian 13     (VMID 9003)"
echo ""

case "$TEMPLATE_ID" in
  9000) TEMPLATE_DISP="Rocky 9" ;;
  9001) TEMPLATE_DISP="Ubuntu 22.04" ;;
  9002) TEMPLATE_DISP="Ubuntu 24.04" ;;
  9003) TEMPLATE_DISP="Debian 13" ;;
  *)    TEMPLATE_DISP="VMID $TEMPLATE_ID" ;;
esac

read -rp "  Template OS         [$TEMPLATE_DISP]: " input
if [ -n "$input" ]; then
  case "$input" in
    1|9000) TEMPLATE_ID=9000 ;;
    2|9001) TEMPLATE_ID=9001 ;;
    3|9002) TEMPLATE_ID=9002 ;;
    4|9003) TEMPLATE_ID=9003 ;;
    *) warn "  Scelta non valida — lascio $TEMPLATE_DISP" ;;
  esac
fi

echo ""

# ── Risorse master ────────────────────────────────────────────────────────────
echo "┌─ RISORSE CONTROL PLANE ──────────────────────────────────────────────────┐"
echo ""

read -rp "  CPU cores          [$MASTER_CPU]: " input
MASTER_CPU="${input:-$MASTER_CPU}"

read -rp "  RAM MB             [$MASTER_MEM]: " input
MASTER_MEM="${input:-$MASTER_MEM}"

read -rp "  Disco GB (0=template) [$MASTER_DISK]: " input
MASTER_DISK="${input:-$MASTER_DISK}"

echo ""

# ── Risorse worker ────────────────────────────────────────────────────────────
echo "┌─ RISORSE WORKER ─────────────────────────────────────────────────────────┐"
echo ""

read -rp "  CPU cores          [$WORKER_CPU]: " input
WORKER_CPU="${input:-$WORKER_CPU}"

read -rp "  RAM MB             [$WORKER_MEM]: " input
WORKER_MEM="${input:-$WORKER_MEM}"

read -rp "  Disco GB (0=template) [$WORKER_DISK]: " input
WORKER_DISK="${input:-$WORKER_DISK}"

echo ""

# ── Riepilogo ─────────────────────────────────────────────────────────────────
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  RIEPILOGO CONFIGURAZIONE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "  Topologia:          ${CTRL_COUNT} control plane + ${WORKER_COUNT} worker"
echo "  Prefissi:           ${MASTER_PREFIX}-X / ${WORKER_PREFIX}-X"
echo "  VM ID:              ${MASTER_VMID}+ / ${WORKER_VMID}+"
echo "  IP:                 ${MASTER_IP_START}+ / ${WORKER_IP_START}+"
echo "  Subnet:             ${K8S_SUBNET}"
echo "  Gateway:            ${K8S_GATEWAY}"
echo "  Template:           VMID ${TEMPLATE_ID}"
echo "  Nodo Proxmox:       ${PROXMOX_NODE}"
echo "  Storage:            ${STORAGE_POOL}"
echo ""
echo "  Master CPU:         ${MASTER_CPU} core"
echo "  Master RAM:         ${MASTER_MEM} MB"
echo "  Master disco:       ${MASTER_DISK} GB${MASTER_DISK:-0}"
echo "  Worker CPU:         ${WORKER_CPU} core"
echo "  Worker RAM:         ${WORKER_MEM} MB"
echo "  Worker disco:       ${WORKER_DISK} GB"
echo ""

read -rp "  Scrivere configurazione? (s/N): " confirm
[[ "$confirm" =~ ^[sSyY] ]] || error "Annullato"

# ── Scrive terraform.tfvars ───────────────────────────────────────────────────
cat > "$TFVARS" << EOF
# Configurazione cluster Kubernetes — Generato da configure-cluster.sh
# Credenziali Proxmox: vedi terraform.auto.tfvars (generato da init-project.sh)

# ── Rete ────────────────────────────────────────────────────────────────────────
proxmox_node = "${PROXMOX_NODE}"
k8s_subnet   = "${K8S_SUBNET}"
k8s_gateway  = "${K8S_GATEWAY}"

# ── Template Packer ─────────────────────────────────────────────────────────────
template_vm_id = ${TEMPLATE_ID}

# ── Nomi VM ─────────────────────────────────────────────────────────────────────
master_name_prefix = "${MASTER_PREFIX}"
worker_name_prefix = "${WORKER_PREFIX}"

# ── Topologia ────────────────────────────────────────────────────────────────────
control_plane_count = ${CTRL_COUNT}
worker_count        = ${WORKER_COUNT}

# ── VM ID ───────────────────────────────────────────────────────────────────────
master_vm_id_start = ${MASTER_VMID}
worker_vm_id_start = ${WORKER_VMID}

# ── IP ──────────────────────────────────────────────────────────────────────────
master_ip_start = ${MASTER_IP_START}
worker_ip_start = ${WORKER_IP_START}

# ── Risorse master ──────────────────────────────────────────────────────────────
master_cpu_cores = ${MASTER_CPU}
master_memory    = ${MASTER_MEM}
master_disk_size = ${MASTER_DISK}

# ── Risorse worker ──────────────────────────────────────────────────────────────
worker_cpu_cores = ${WORKER_CPU}
worker_memory    = ${WORKER_MEM}
worker_disk_size = ${WORKER_DISK}
EOF

ok "Configurazione scritta in: $TFVARS"
echo ""

info "Prossimi passi:"
info "  terraform plan    — verifica le modifiche"
info "  terraform apply   — crea le VM del cluster"
echo ""
