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
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${GREEN}[kubespray]${NC} $*"; }
ok()    { echo -e "${BLUE}[kubespray]${NC} $*"; }
warn()  { echo -e "${YELLOW}[kubespray]${NC} $*"; }
error() { echo -e "${RED}[kubespray]${NC} $*" >&2; exit 1; }

# ── Inventory: auto-copia da Terraform se disponibile ──────────────────────
TERRAFORM_INVENTORY="$SCRIPT_DIR/../terraform/generated/kubespray-inventory.ini"
if [ -f "$TERRAFORM_INVENTORY" ]; then
  if [ ! -f "$INVENTORY" ] || [ "$TERRAFORM_INVENTORY" -nt "$INVENTORY" ]; then
    cp "$TERRAFORM_INVENTORY" "$INVENTORY"
    info "Inventory auto-aggiornato da Terraform: $INVENTORY"
  fi
fi
[ -f "$INVENTORY" ] || error "Inventory non trovato: $INVENTORY
  Eseguire prima:
    cd ../terraform && terraform apply"

[ -d "$VENV_DIR" ] || error "Venv Python non trovato: $VENV_DIR
  Eseguire prima setup-bastion.sh"

[ -f "$HOME/.ssh/id_rsa" ] || error "Chiave SSH non trovata: ~/.ssh/id_rsa
  Eseguire prima setup-bastion.sh"

# ── Applica patch necessarie a Kubespray ────────────────────────────────────────
_apply_patches() {
  local f="$KUBESPRAY_DIR/roles/download/tasks/download_container.yml"
  if grep -q 'failed_when: container_save_status.stderr' "$f" 2>/dev/null; then
    info "Applicando patch: nerdctl stderr → rc check..."
    sed -i 's/failed_when: container_save_status.stderr/failed_when: container_save_status.rc != 0/' "$f"
    ok "Patch applicata."
  fi
}

# ── Clone Kubespray se non presente ──────────────────────────────────────────
if [ ! -d "$KUBESPRAY_DIR" ]; then
  info "Clonando Kubespray in $KUBESPRAY_DIR..."
  git clone --depth 1 https://github.com/kubernetes-sigs/kubespray.git "$KUBESPRAY_DIR"
  info "Clone completato."
else
  info "Kubespray trovato in $KUBESPRAY_DIR"
fi

_apply_patches

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

# ── SSH ping test pre-deploy ──────────────────────────────────────────────────
_ssh_ping_test() {
  local fail=0
  info "Verifica connettività SSH verso tutti i nodi..."
  while IFS= read -r line; do
    host=$(echo "$line" | awk '{print $1}')
    ip=$(echo "$line" | grep -oP 'ansible_host=\K[0-9.]+')
    [ -z "$ip" ] && continue
    echo -n "  $host ($ip) ... "
    if ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=no ubuntu@"$ip" "echo OK" 2>/dev/null; then
      echo "OK"
    else
      echo "NO"
      fail=1
    fi
  done < <(grep 'ansible_host=' "$INVENTORY")
  if [ "$fail" -eq 1 ]; then
    warn "Uno o più nodi non sono raggiungibili via SSH."
    read -r -p "  Procedere comunque con l'installazione? (s/N): " confirm
    [[ "$confirm" =~ ^[sSyY] ]] || error "Annullato"
  else
    ok "Tutti i nodi raggiungibili"
  fi
}

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

# ── Esegui il comando richiesto ───────────────────────────────────────────────
case "$COMMAND" in

  install)
    info "Avvio installazione cluster Kubernetes..."
    info "Inventory: $INVENTORY"
    _ssh_ping_test
    warn "Durata stimata: 20-40 minuti a seconda dell'hardware."
    "${ANSIBLE_CMD[@]}" cluster.yml
    info "Cluster installato con successo!"

    # ── Copia kubectl e kubeconfig sul bastion ──────────────────────────────────
    local artifacts
    artifacts="$(dirname "$INVENTORY")/artifacts"
    if [ -f "$artifacts/kubectl" ] && [ -f "$artifacts/admin.conf" ]; then
      install -m 755 "$artifacts/kubectl" /usr/local/bin/kubectl
      mkdir -p ~/.kube
      cp "$artifacts/admin.conf" ~/.kube/config
      chmod 600 ~/.kube/config
      ok "kubectl e kubeconfig installati su ~/.kube/config"
    fi

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
