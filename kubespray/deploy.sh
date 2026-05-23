#!/usr/bin/env bash
# Deploy / gestione cluster Kubernetes con Kubespray.
#
# Uso:
#   ./deploy.sh                          # installa il cluster
#   ./deploy.sh upgrade                  # aggiorna Kubernetes alla versione in group_vars
#   ./deploy.sh remove-node <hostname>   # rimuove un nodo dal cluster
#   ./deploy.sh reset                    # rimuove completamente Kubernetes dai nodi
#
# Variabili d'ambiente opzionali:
#   KUBESPRAY_DIR   path al repo Kubespray  (default: ~/kubespray)
#   VENV_DIR        path al venv Python     (default: ~/kubespray-env)
#   INVENTORY       path all'inventory      (default: ./inventory/homelab/hosts.ini)
#   EXTRA_ARGS      argomenti extra per ansible-playbook (es. "--limit k8s-worker-1")
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBESPRAY_DIR="${KUBESPRAY_DIR:-$HOME/kubespray}"
VENV_DIR="${VENV_DIR:-$HOME/kubespray-env}"
INVENTORY="${INVENTORY:-$SCRIPT_DIR/inventory/homelab/hosts.ini}"
COMMAND="${1:-install}"

# ── Colori ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[kubespray]${NC} $*"; }
warn()  { echo -e "${YELLOW}[kubespray]${NC} $*"; }
error() { echo -e "${RED}[kubespray]${NC} $*" >&2; exit 1; }

# ── Verifica prerequisiti ─────────────────────────────────────────────────────
[ -f "$INVENTORY" ] || error "Inventory non trovato: $INVENTORY
  Eseguire prima:
    cd ../terraform && terraform apply
    cp terraform/generated/kubespray-inventory.ini \\
       kubespray/inventory/homelab/hosts.ini"

[ -d "$VENV_DIR" ] || error "Venv Python non trovato: $VENV_DIR
  Eseguire prima setup-bastion.sh"

[ -f "$HOME/.ssh/id_rsa" ] || error "Chiave SSH non trovata: ~/.ssh/id_rsa
  Eseguire prima setup-bastion.sh"

# ── Clone Kubespray se non presente ──────────────────────────────────────────
if [ ! -d "$KUBESPRAY_DIR" ]; then
  info "Clonando Kubespray in $KUBESPRAY_DIR..."
  git clone --depth 1 https://github.com/kubernetes-sigs/kubespray.git "$KUBESPRAY_DIR"
  info "Clone completato."
else
  info "Kubespray trovato in $KUBESPRAY_DIR"
fi

# ── Attiva venv ───────────────────────────────────────────────────────────────
info "Attivando venv: $VENV_DIR"
# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"

# ── Cambia directory nel repo Kubespray ───────────────────────────────────────
# ansible-playbook deve girare dalla root del repo per trovare ruoli e collezioni.
# Il nostro ansible.cfg viene ignorato qui — usa quello di Kubespray.
cd "$KUBESPRAY_DIR"

ANSIBLE_CMD=(
  ansible-playbook
  -i "$INVENTORY"
  --private-key ~/.ssh/id_rsa
  --become
)

# Aggiunge argomenti extra se definiti
if [ -n "${EXTRA_ARGS:-}" ]; then
  # shellcheck disable=SC2206
  ANSIBLE_CMD+=($EXTRA_ARGS)
fi

# ── Esegui il comando richiesto ───────────────────────────────────────────────
case "$COMMAND" in

  install)
    info "Avvio installazione cluster Kubernetes..."
    info "Inventory: $INVENTORY"
    warn "Durata stimata: 20-40 minuti a seconda dell'hardware."
    "${ANSIBLE_CMD[@]}" cluster.yml
    info "Cluster installato con successo!"
    _print_post_install
    ;;

  upgrade)
    K8S_VER=$(grep '^kube_version:' \
      "$SCRIPT_DIR/inventory/homelab/group_vars/k8s_cluster/k8s-cluster.yml" \
      | awk '{print $2}')
    info "Upgrade cluster a Kubernetes $K8S_VER..."
    warn "Processo non distruttivo ma richiede un drain/uncordon di ogni nodo."
    "${ANSIBLE_CMD[@]}" upgrade-cluster.yml
    info "Upgrade completato."
    ;;

  remove-node)
    NODE="${2:-}"
    [ -n "$NODE" ] || error "Specificare il nome del nodo: ./deploy.sh remove-node <hostname>"
    info "Rimozione nodo: $NODE"
    warn "Il nodo verrà drenato e rimosso dal cluster."
    "${ANSIBLE_CMD[@]}" remove-node.yml \
      -e "node=$NODE" \
      -e "skip_confirmation=yes"
    info "Nodo $NODE rimosso. Ricordarsi di eseguire 'terraform apply' per distruggere la VM."
    ;;

  reset)
    warn "ATTENZIONE: questa operazione rimuove Kubernetes da tutti i nodi!"
    read -r -p "Digitare 'reset' per confermare: " CONFIRM
    [ "$CONFIRM" = "reset" ] || { info "Operazione annullata."; exit 0; }
    "${ANSIBLE_CMD[@]}" reset.yml -e "reset_confirmation=yes"
    info "Reset completato. Il cluster è stato rimosso."
    ;;

  *)
    error "Comando non riconosciuto: $COMMAND
  Comandi disponibili: install | upgrade | remove-node <hostname> | reset"
    ;;

esac

# ── Info post-installazione ────────────────────────────────────────────────────
_print_post_install() {
  MASTER_IP=$(grep ansible_host "$INVENTORY" | grep master | head -1 | awk -F'ansible_host=' '{print $2}' | awk '{print $1}')
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Cluster Kubernetes pronto!"
  echo ""
  echo "  kubeconfig scaricato in: ~/.kube/config"
  echo "  kubectl disponibile in:  /usr/local/bin/kubectl"
  echo ""
  echo "  Comandi di verifica:"
  echo "    kubectl get nodes"
  echo "    kubectl get pods -A"
  echo ""
  if [ -n "${MASTER_IP:-}" ]; then
  echo "  API server: https://${MASTER_IP}:6443"
  fi
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}
