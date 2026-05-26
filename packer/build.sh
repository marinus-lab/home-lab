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
  echo "  4) Debian 13"
  echo "  5) Tutti (22.04 + 24.04 + Rocky 9 + Debian 13)"
  echo ""
  read -rp "Seleziona (1-5): " choice
  echo ""

  case "$choice" in
    1) DISTRIBUTIONS=("ubuntu-22.04") ;;
    2) DISTRIBUTIONS=("ubuntu-24.04") ;;
    3) DISTRIBUTIONS=("rocky-9") ;;
    4) DISTRIBUTIONS=("debian-13") ;;
    5) DISTRIBUTIONS=("ubuntu-22.04" "ubuntu-24.04" "rocky-9" "debian-13") ;;
    *) error "Scelta non valida"; ;;
  esac
else
  case "$DISTRIBUTION" in
    ubuntu-22.04|ubuntu-24.04|rocky-9|debian-13) DISTRIBUTIONS=("$DISTRIBUTION") ;;
    *) error "Distribuzione non valida: $DISTRIBUTION"; ;;
  esac
fi

# ── Password per gli utenti ────────────────────────────────────────────────────
UBUNTU_PASSWORD="${UBUNTU_PASSWORD:-ubuntu}"
ROCKY_PASSWORD="${ROCKY_PASSWORD:-rocky}"
DEBIAN_PASSWORD="${DEBIAN_PASSWORD:-debian}"
ROOT_PASSWORD="${ROOT_PASSWORD:-packer}"

# ── Genera hash per Ubuntu
UBUNTU_PASSWORD_HASH=$(openssl passwd -6 "${UBUNTU_PASSWORD}")

# ── Genera hash per Debian
DEBIAN_PASSWORD_HASH=$(openssl passwd -6 "${DEBIAN_PASSWORD}")

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

  # Log file per output completo
  LOGS_DIR="$SCRIPT_DIR/logs"
  mkdir -p "$LOGS_DIR"
  TIMESTAMP=$(date +%Y%m%d-%H%M%S)
  BUILD_LOG="$LOGS_DIR/build-$dist-$TIMESTAMP.log"

  # Mappa distribuzione -> filtro -only di Packer (<build_name>.<source>)
  case "$dist" in
    ubuntu-22.04) ONLY_FILTER="ubuntu-2204.proxmox-iso.ubuntu_2204" ;;
    ubuntu-24.04) ONLY_FILTER="ubuntu-2404.proxmox-iso.ubuntu_2404" ;;
    rocky-9)      ONLY_FILTER="rocky-9.proxmox-iso.rocky" ;;
    debian-13)    ONLY_FILTER="debian-13.proxmox-iso.debian_13" ;;
  esac

  case "$dist" in
    ubuntu-22.04|ubuntu-24.04)
      # Genera user-data per Ubuntu
      sed \
        -e "s|%%UBUNTU_PASSWORD_HASH%%|${UBUNTU_PASSWORD_HASH}|g" \
        -e "s|%%ROOT_PASSWORD%%|${ROOT_PASSWORD}|g" \
        http/ubuntu-user-data.tpl > http/user-data

      ok "http/user-data generato (Ubuntu)"
      ;;

    rocky-9)
      # Genera kickstart per Rocky
      sed \
        -e "s|%%ROOT_PASSWORD%%|${ROOT_PASSWORD_HASH}|g" \
        -e "s|%%ROCKY_PASSWORD_HASH%%|${ROCKY_PASSWORD_HASH}|g" \
        http/rocky-ks.cfg.tpl > http/rocky-ks.cfg

      ok "http/rocky-ks.cfg generato (Rocky)"
      ;;

    debian-13)
      # Genera preseed per Debian
      sed \
        -e "s|%%ROOT_PASSWORD_HASH%%|${ROOT_PASSWORD_HASH}|g" \
        -e "s|%%DEBIAN_PASSWORD_HASH%%|${DEBIAN_PASSWORD_HASH}|g" \
        http/debian-preseed.cfg.tpl > http/debian-preseed.cfg

      ok "http/debian-preseed.cfg generato (Debian)"
      ;;
  esac

  # ── Pre-check: VM esistente su Proxmox? ────────────────────────────────────
  case "$dist" in
    ubuntu-22.04) VM_ID=9001 ;;
    ubuntu-24.04) VM_ID=9002 ;;
    rocky-9)      VM_ID=9000 ;;
    debian-13)    VM_ID=9003 ;;
  esac

  PROXMOX_NODE=$(grep -E '^\s*proxmox_node\s*=' "$PKRVARS_FILE" | sed 's/.*= *"\(.*\)".*/\1/')
  PROXMOX_API=$(grep -E '^\s*proxmox_url\s*=' "$PKRVARS_FILE" | sed 's/.*= *"\(.*\)".*/\1/')
  PROXMOX_TID=$(grep -E '^\s*proxmox_token_id\s*=' "$PKRVARS_FILE" | sed 's/.*= *"\(.*\)".*/\1/')
  PROXMOX_TSEC=$(grep -E '^\s*proxmox_token_secret\s*=' "$PKRVARS_FILE" | sed 's/.*= *"\(.*\)".*/\1/')

  if [ -n "$PROXMOX_API" ] && [ -n "$PROXMOX_TID" ] && [ -n "$PROXMOX_TSEC" ] && \
     curl -sfk \
       -H "Authorization: PVEAPIToken=${PROXMOX_TID}=${PROXMOX_TSEC}" \
       "${PROXMOX_API}/nodes/${PROXMOX_NODE}/qemu/${VM_ID}/status/current" > /dev/null 2>&1; then
    echo ""
    echo -e "${YELLOW}⚠️  VM $VM_ID ($dist) already exists on node '$PROXMOX_NODE'${NC}"
    echo -e "${YELLOW}   Packer non può creare una VM con lo stesso ID.${NC}"
    read -rp "$(echo -e "Overwrite with ${YELLOW}-force${NC}? ${YELLOW}(y/N)${NC}: ")" answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
      PACKER_ARGS="${PACKER_ARGS:-} -force"
      echo -e "${GREEN}✓${NC} Will overwrite VM $VM_ID"
    else
      error "Build aborted for $dist"
    fi
  fi

  # ── Pre-check: ISO presente su Proxmox? ──────────────────────────────────────
  case "$dist" in
    ubuntu-22.04) ISO_FILE="ubuntu-22.04.5-live-server-amd64.iso" ;;
    ubuntu-24.04) ISO_FILE="ubuntu-24.04.4-live-server-amd64.iso" ;;
    rocky-9)      ISO_FILE="Rocky-9-latest-x86_64-boot.iso" ;;
    debian-13)    ISO_FILE="debian-13.5.0-amd64-netinst.iso" ;;
  esac

  ISO_STORAGE=$(grep -E '^\s*iso_storage_pool\s*=' "$PKRVARS_FILE" | sed 's/.*= *"\(.*\)".*/\1/')
  if [ -n "$PROXMOX_API" ] && [ -n "$PROXMOX_TID" ] && [ -n "$PROXMOX_TSEC" ] && [ -n "$ISO_STORAGE" ]; then
    if ! curl -sfk \
      -H "Authorization: PVEAPIToken=${PROXMOX_TID}=${PROXMOX_TSEC}" \
      "${PROXMOX_API}/nodes/${PROXMOX_NODE}/storage/${ISO_STORAGE}/content/${ISO_STORAGE}:iso/${ISO_FILE}" > /dev/null 2>&1; then
      error "ISO mancante: ${ISO_STORAGE}:iso/${ISO_FILE}. Per scaricare: cd ${SCRIPT_DIR} && ./download-isos.sh"
    fi
  fi

  # Inizializza plugins Packer (legge tutta la directory)
  packer init "$SCRIPT_DIR"

  # Build: passa la directory così Packer carica variables.pkr.hcl + tutti i .pkr.hcl
  # Usa -only per limitare la build alla distribuzione selezionata
  info "Build in corso — log: $BUILD_LOG"
  packer build \
    -var-file="$PKRVARS_FILE" \
    -only="$ONLY_FILTER" \
    ${PACKER_ARGS:-} \
    "$SCRIPT_DIR" > "$BUILD_LOG" 2>&1 && \
  ok "Build completata: $dist (log: $BUILD_LOG)" || \
  error "Build FALLITA: $dist (log: $BUILD_LOG)"
done
