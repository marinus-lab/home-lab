#!/usr/bin/env bash
# Build Packer per multiple distribuzioni Linux (Ubuntu 22.04, Ubuntu 24.04, Rocky 9)
set -euo pipefail

# ── Colori ────────────────────────────────────────────────────────────────────
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${BLUE}[packer]${NC} $*"; }
ok()    { echo -e "${GREEN}[packer]${NC} ✅ $*"; }
error() { echo -e "${RED}[packer]${NC} ❌ $*" >&2; exit 1; }

# ── Selezione distribuzione ────────────────────────────────────────────────────
DISTRIBUTION="${1:-}"

if [ -z "$DISTRIBUTION" ]; then
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  SELEZIONE DISTRIBUZIONE LINUX"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "Quali template desideri buildare?"
  echo "  1) Ubuntu 22.04 LTS"
  echo "  2) Ubuntu 24.04 LTS"
  echo "  3) Rocky Linux 9"
  echo "  4) Tutti (22.04 + 24.04 + Rocky 9)"
  echo ""
  read -rp "Seleziona (1-4): " choice
  echo ""

  case "$choice" in
    1) DISTRIBUTIONS=("ubuntu-22.04") ;;
    2) DISTRIBUTIONS=("ubuntu-24.04") ;;
    3) DISTRIBUTIONS=("rocky-9") ;;
    4) DISTRIBUTIONS=("ubuntu-22.04" "ubuntu-24.04" "rocky-9") ;;
    *) error "Scelta non valida"; ;;
  esac
else
  case "$DISTRIBUTION" in
    ubuntu-22.04|ubuntu-24.04|rocky-9) DISTRIBUTIONS=("$DISTRIBUTION") ;;
    *) error "Distribuzione non valida: $DISTRIBUTION"; ;;
  esac
fi

# ── Password per gli utenti ────────────────────────────────────────────────────
UBUNTU_PASSWORD="${UBUNTU_PASSWORD:-ubuntu}"
ROCKY_PASSWORD="${ROCKY_PASSWORD:-rocky}"
ROOT_PASSWORD="${ROOT_PASSWORD:-packer}"

# ── Genera hash per Ubuntu
UBUNTU_PASSWORD_HASH=$(openssl passwd -6 "${UBUNTU_PASSWORD}")

# ── Genera hash criptato per Rocky (Packer usa formato criptato)
ROCKY_PASSWORD_HASH=$(openssl passwd -6 "${ROCKY_PASSWORD}")
ROOT_PASSWORD_HASH=$(openssl passwd -6 "${ROOT_PASSWORD}")

# ── Verifica file di configurazione Packer ────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKRVARS_FILE="$SCRIPT_DIR/packer.pkrvars.hcl"

if [ ! -f "$PKRVARS_FILE" ]; then
  error "File $PKRVARS_FILE non trovato. Esegui prima 'bash init-project.sh' dalla root del progetto"
fi

ok "Configurazione Packer trovata: $PKRVARS_FILE"

# ── Build per ogni distribuzione ──────────────────────────────────────────────
mkdir -p http

for dist in "${DISTRIBUTIONS[@]}"; do
  info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  info "Build: $dist"
  info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  case "$dist" in
    ubuntu-22.04|ubuntu-24.04)
      # Genera user-data per Ubuntu
      sed \
        -e "s|%%UBUNTU_PASSWORD_HASH%%|${UBUNTU_PASSWORD_HASH}|g" \
        -e "s|%%ROOT_PASSWORD%%|${ROOT_PASSWORD}|g" \
        http/ubuntu-user-data.tpl > http/user-data

      ok "http/user-data generato (Ubuntu)"

      # Inizializza plugin Packer
      packer init "${dist}.pkr.hcl"

      # Build con var-file
      packer build -var-file="$PKRVARS_FILE" ${PACKER_ARGS:-} "${dist}.pkr.hcl"
      ;;

    rocky-9)
      # Genera kickstart per Rocky
      sed \
        -e "s|%%ROOT_PASSWORD%%|${ROOT_PASSWORD_HASH}|g" \
        -e "s|%%ROCKY_PASSWORD_HASH%%|${ROCKY_PASSWORD_HASH}|g" \
        http/rocky-ks.cfg.tpl > http/rocky-ks.cfg

      ok "http/rocky-ks.cfg generato (Rocky)"

      # Inizializza plugin Packer
      packer init rocky-9.pkr.hcl

      # Build con var-file
      packer build -var-file="$PKRVARS_FILE" ${PACKER_ARGS:-} rocky-9.pkr.hcl
      ;;
  esac

  echo ""
done

ok "Build completata per: ${DISTRIBUTIONS[*]}"
