#!/usr/bin/env bash
# Deploy / gestione cluster K3S.
#
# Uso:
#   ./deploy.sh install        # Fase 1: installa K3S su primo nodo (single-node)
#   ./deploy.sh join            # Fase 2: aggiunge gli altri nodi (HA 3 server)
#   ./deploy.sh reset           # Disinstalla K3S da tutti i nodi
#
# Variabili d'ambiente opzionali:
#   INVENTORY   path all'inventory  (default: ./inventory.ini)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVENTORY="${INVENTORY:-$SCRIPT_DIR/inventory.ini}"
COMMAND="${1:-help}"

# ── Colori ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[k3s]${NC} $*"; }
ok()    { echo -e "${GREEN}[k3s]${NC} $*"; }
warn()  { echo -e "${YELLOW}[k3s]${NC} $*"; }
error() { echo -e "${RED}[k3s]${NC} $*" >&2; exit 1; }

# ── Inventory: auto-copia da Terraform se disponibile ──────────────────────
_auto_inventory() {
  local generated="$SCRIPT_DIR/../terraform-k3s/generated/k3s-inventory.ini"
  if [ -f "$generated" ]; then
    if [ ! -f "$INVENTORY" ] || [ "$generated" -nt "$INVENTORY" ]; then
      cp "$generated" "$INVENTORY"
      info "Inventory auto-aggiornato da Terraform: $INVENTORY"
    fi
  fi
  [ -f "$INVENTORY" ] || error "Inventory non trovato: $INVENTORY
  Eseguire prima:
    cd terraform-k3s && terraform apply"
}

# ── Legge la lista nodi dall'inventory ─────────────────────────────────────
_read_nodes() {
  local group="${1:-k3s_cluster}"
  awk -v g="$group" '
    /^\['"$group"'\]/ { found=1; next }
    found && /^$/      { found=0 }
    found && /^\[/     { found=0 }
    found && NF        { print }
  ' "$INVENTORY"
}

# ── SSH helper ──────────────────────────────────────────────────────────────
_ssh() {
  local host="$1"; shift
  local ip; ip=$(grep "^$host " "$INVENTORY" | grep -oP 'ansible_host=\K[0-9.]+' || true)
  [ -n "$ip" ] || error "Nodo $host non trovato in $INVENTORY"
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 ubuntu@"$ip" "$@"
}

# ── Fase 1: installa K3S sul primo nodo ────────────────────────────────────
_install() {
  _auto_inventory

  # Identifica il primo nodo
  local first; first=$(_read_nodes | head -1 | awk '{print $1}')
  [ -n "$first" ] || error "Nessun nodo trovato in $INVENTORY"
  local first_ip; first_ip=$(grep "^$first " "$INVENTORY" | grep -oP 'ansible_host=\K[0-9.]+')

  info "Fase 1 — Installazione K3S su $first ($first_ip)..."

  # Verifica che non sia già installato
  if _ssh "$first" "command -v k3s &>/dev/null"; then
    warn "K3S già installato su $first"
    read -r -p "  Procedere comunque? (s/N): " confirm
    [[ "$confirm" =~ ^[sSyY] ]] || error "Annullato"
  fi

  # Installa K3S server con cluster-init (embedded etcd)
  info "Avvio installazione K3S su $first..."
  _ssh "$first" "curl -sfL https://get.k3s.io | sh -s - --cluster-init --tls-san $first_ip" </dev/null
  ok "K3S installato su $first"

  # Attendi che il nodo sia Ready
  info "Attendo che il nodo sia Ready..."
  sleep 5
  _ssh "$first" "k3s kubectl wait --for=condition=Ready node/$first --timeout=120s" 2>/dev/null || true
  ok "Nodo $first pronto"

  # Copia kubeconfig sul bastion
  info "Copio kubeconfig sul bastion..."
  mkdir -p ~/.kube
  _ssh "$first" "sudo cat /etc/rancher/k3s/k3s.yaml" | sed "s/127.0.0.1/$first_ip/g" > ~/.kube/k3s-config
  chmod 600 ~/.kube/k3s-config
  ok "kubeconfig in ~/.kube/k3s-config"

  # Salva token per la fase 2
  info "Salvo token di join..."
  _ssh "$first" "sudo cat /var/lib/rancher/k3s/server/node-token" > "$SCRIPT_DIR/.k3s-token"
  chmod 600 "$SCRIPT_DIR/.k3s-token"
  ok "Token salvato in .k3s-token"

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  K3S single-node pronto su $first ($first_ip)"
  echo ""
  echo "  kubectl --kubeconfig ~/.kube/k3s-config get nodes"
  echo "  kubectl --kubeconfig ~/.kube/k3s-config get pods -A"
  echo ""
  echo "  Per aggiungere gli altri nodi:"
  echo "    ./deploy.sh join"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ── Fase 2: join degli altri nodi al cluster ───────────────────────────────
_join() {
  _auto_inventory

  # Legge token
  [ -f "$SCRIPT_DIR/.k3s-token" ] || error "Token non trovato (.k3s-token).
  Eseguire prima: ./deploy.sh install"
  local token; token=$(cat "$SCRIPT_DIR/.k3s-token")
  [ -n "$token" ] || error "Token vuoto"

  # Identifica il primo nodo (server esistente)
  local first; first=$(_read_nodes | head -1 | awk '{print $1}')
  local first_ip; first_ip=$(grep "^$first " "$INVENTORY" | grep -oP 'ansible_host=\K[0-9.]+')

  # Identifica gli altri nodi
  local others; others=$(_read_nodes | awk '{print $1}' | tail -n +2)
  [ -n "$others" ] || error "Nessun nodo aggiuntivo trovato in $INVENTORY"

  info "Fase 2 — Join nodi al cluster K3S (server: $first @ $first_ip)"

  for node in $others; do
    local ip; ip=$(grep "^$node " "$INVENTORY" | grep -oP 'ansible_host=\K[0-9.]+')

    # Verifica che non sia già joined
    if _ssh "$node" "command -v k3s &>/dev/null"; then
      warn "K3S già installato su $node, salto"
      continue
    fi

    info "Join di $node ($ip)..."
    _ssh "$node" "curl -sfL https://get.k3s.io | sh -s - --server https://$first_ip:6443 --token $token" </dev/null
    ok "$node joined"

    # Attendi che il nodo sia Ready
    _ssh "$first" "k3s kubectl wait --for=condition=Ready node/$node --timeout=120s" 2>/dev/null || true
    ok "$node pronto"
  done

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Cluster K3S HA pronto!"
  echo ""
  echo "  kubectl --kubeconfig ~/.kube/k3s-config get nodes"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ── Reset: disinstalla K3S da tutti i nodi ─────────────────────────────────
_reset() {
  _auto_inventory

  warn "ATTENZIONE: questa operazione rimuove K3S da tutti i nodi!"
  read -r -p "Digitare 'reset' per confermare: " confirm
  [ "$confirm" = "reset" ] || { info "Operazione annullata."; exit 0; }

  local nodes; nodes=$(_read_nodes | awk '{print $1}')
  for node in $nodes; do
    info "Disinstallo K3S da $node..."
    _ssh "$node" "sudo /usr/local/bin/k3s-uninstall.sh 2>/dev/null; sudo /usr/local/bin/k3s-agent-uninstall.sh 2>/dev/null; echo 'done'" </dev/null || true
    ok "K3S rimosso da $node"
  done

  # Pulisce file locali
  rm -f "$SCRIPT_DIR/.k3s-token"
  rm -f ~/.kube/k3s-config
  ok "Token e kubeconfig locali rimossi"
}

# ── Help ────────────────────────────────────────────────────────────────────
_help() {
  echo "Uso: $0 <comando>"
  echo ""
  echo "Comandi:"
  echo "  install     Fase 1: installa K3S single-node sul primo nodo"
  echo "  join        Fase 2: aggiunge gli altri nodi al cluster HA"
  echo "  reset       Disinstalla K3S da tutti i nodi"
  echo ""
  echo "Variabili:"
  echo "  INVENTORY   path all'inventory  (default: ./inventory.ini)"
}

# ── Main ────────────────────────────────────────────────────────────────────
case "$COMMAND" in
  install) _install ;;
  join)    _join ;;
  reset)   _reset ;;
  help|*)  _help ;;
esac
