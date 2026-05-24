#!/usr/bin/env bash
# Crea una singola VM su Proxmox per test — usa lo stesso modulo del cluster K8s
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SINGLE_DIR="$SCRIPT_DIR/single-vm"
AUTO_TFVARS="$SCRIPT_DIR/terraform.auto.tfvars"
TFVARS="$SCRIPT_DIR/terraform.tfvars"

# ── Colori ────────────────────────────────────────────────────────────────────
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${BLUE}[create-vm]${NC} $*"; }
ok()    { echo -e "${GREEN}[create-vm]${NC} $*"; }
warn()  { echo -e "${YELLOW}[create-vm]${NC} $*"; }
error() { echo -e "${RED}[create-vm]${NC} $*" >&2; exit 1; }

# ── Helper: estrae valore da file .tfvars ─────────────────────────────────────
read_var() {
  local key="$1" file="$2"
  grep -E "^\s*${key}\s*=" "$file" 2>/dev/null | head -1 \
    | sed -E "s/^\s*${key}\s*=\s*//" \
    | sed -E 's/[[:space:]]*#.*$//' \
    | sed -E 's/^"|"$//g'
}

# ── Verifica file di configurazione ───────────────────────────────────────────
[ -f "$AUTO_TFVARS" ] || error "File non trovato: $AUTO_TFVARS (esegui prima init-project.sh)"
[ -f "$TFVARS" ]      || error "File non trovato: $TFVARS"

# ── Legge credenziali da terraform.auto.tfvars ────────────────────────────────
PROXMOX_URL=$(read_var proxmox_url "$AUTO_TFVARS")
PROXMOX_TOKEN_ID=$(read_var proxmox_token_id "$AUTO_TFVARS")
PROXMOX_TOKEN_SECRET=$(read_var proxmox_token_secret "$AUTO_TFVARS")
PROXMOX_NODE=$(read_var proxmox_node "$AUTO_TFVARS")
STORAGE_POOL=$(read_var storage_pool "$AUTO_TFVARS")
K8S_SUBNET=$(read_var k8s_subnet "$AUTO_TFVARS")
K8S_GATEWAY=$(read_var k8s_gateway "$AUTO_TFVARS")

# ── Default da terraform.tfvars (con fallback) ────────────────────────────────
NETWORK_BRIDGE=$(read_var network_bridge "$TFVARS")  || NETWORK_BRIDGE=$(read_var network_bridge "$AUTO_TFVARS")
NETWORK_BRIDGE="${NETWORK_BRIDGE:-vmbr0}"

CIDR_PREFIX="${K8S_SUBNET##*/}"
CIDR_PREFIX="${CIDR_PREFIX:-24}"
GATEWAY="${K8S_GATEWAY}"

# ── Mappa OS template → VM ID ─────────────────────────────────────────────────
declare -A TEMPLATES=(
  ["Rocky 9"]="9000"
  ["Ubuntu 22.04"]="9001"
  ["Ubuntu 24.04"]="9002"
)
TEMPLATE_NAMES=("Rocky 9" "Ubuntu 22.04" "Ubuntu 24.04")

echo ""
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info "  CREAZIONE SINGOLA VM DI TEST"
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── Scegli template OS ────────────────────────────────────────────────────────
echo "Template OS disponibili:"
for i in "${!TEMPLATE_NAMES[@]}"; do
  name="${TEMPLATE_NAMES[$i]}"
  echo "  $((i+1))) $name  (VMID ${TEMPLATES[$name]})"
done
echo ""
read -rp "Scegli il template OS (1-${#TEMPLATE_NAMES[@]}): " os_choice
OS_INDEX=$((os_choice - 1))
[ "$OS_INDEX" -ge 0 ] && [ "$OS_INDEX" -lt "${#TEMPLATE_NAMES[@]}" ] || error "Scelta non valida"
OS_NAME="${TEMPLATE_NAMES[$OS_INDEX]}"
TEMPLATE_VM_ID="${TEMPLATES[$OS_NAME]}"

# ── Parametri VM ──────────────────────────────────────────────────────────────
echo ""
read -rp "Nome VM [test-${OS_NAME,,}]: " VM_NAME
VM_NAME="${VM_NAME:-test-${OS_NAME,,}}"

read -rp "VM ID [300]: " VM_ID
VM_ID="${VM_ID:-300}"

read -rp "Indirizzo IP [192.168.1.100]: " IP_ADDRESS
IP_ADDRESS="${IP_ADDRESS:-192.168.1.100}"

read -rp "Prefisso CIDR [$CIDR_PREFIX]: " input
CIDR_PREFIX="${input:-$CIDR_PREFIX}"

read -rp "Gateway [$GATEWAY]: " input
GATEWAY="${input:-$GATEWAY}"

read -rp "Core CPU [2]: " CORES
CORES="${CORES:-2}"

read -rp "RAM MB [2048]: " MEMORY
MEMORY="${MEMORY:-2048}"

read -rp "Disco GB [20]: " DISK_SIZE
DISK_SIZE="${DISK_SIZE:-20}"

# ── Riepilogo ─────────────────────────────────────────────────────────────────
echo ""
info "━━━ Riepilogo ─━━"
echo "  OS:       $OS_NAME (template VMID $TEMPLATE_VM_ID)"
echo "  Nome:     $VM_NAME"
echo "  VM ID:    $VM_ID"
echo "  IP:       $IP_ADDRESS/$CIDR_PREFIX"
echo "  Gateway:  $GATEWAY"
echo "  CPU:      $CORES core"
echo "  RAM:      $MEMORY MB"
echo "  Disco:    $DISK_SIZE GB"
echo "  Nodo:     $PROXMOX_NODE"
echo "  Storage:  $STORAGE_POOL"
echo ""

read -rp "Procedere con la creazione? (s/N): " confirm
[[ "$confirm" =~ ^[sSyY] ]] || error "Annullato"

# ── Genera .auto.tfvars temporaneo ───────────────────────────────────────────
AUTO_FILE="$SINGLE_DIR/single-vm.auto.tfvars"
cat > "$AUTO_FILE" <<EOF
# Generato da create-vm.sh — eliminato dopo terraform destroy
proxmox_url          = "$PROXMOX_URL"
proxmox_token_id     = "$PROXMOX_TOKEN_ID"
proxmox_token_secret = "$PROXMOX_TOKEN_SECRET"
proxmox_node         = "$PROXMOX_NODE"
storage_pool         = "$STORAGE_POOL"
network_bridge       = "$NETWORK_BRIDGE"
template_vm_id       = $TEMPLATE_VM_ID
vm_name              = "$VM_NAME"
vm_id                = $VM_ID
ip_address           = "$IP_ADDRESS"
cidr_prefix          = "$CIDR_PREFIX"
gateway              = "$GATEWAY"
dns_servers          = ["1.1.1.1", "8.8.8.8"]
domain               = "homelab.local"
cores                = $CORES
memory               = $MEMORY
disk_size            = $DISK_SIZE
ssh_public_key_path  = "~/.ssh/id_rsa.pub"
EOF

info "File temporaneo creato: $AUTO_FILE"
echo ""

# ── Terraform ─────────────────────────────────────────────────────────────────
cd "$SINGLE_DIR"

info "Inizializzazione Terraform..."
terraform init -upgrade 2>&1 | sed 's/^/  /'

echo ""
info "Creazione VM..."
terraform apply -auto-approve 2>&1 | sed 's/^/  /'

echo ""
ok "VM creata con successo!"
terraform output 2>/dev/null

echo ""
info "Per eliminare la VM: cd $SINGLE_DIR && terraform destroy"
info "File temporaneo: $AUTO_FILE"
echo ""
