#!/usr/bin/env bash
# Scarica/verifica ISO su Proxmox per le build Packer
set -euo pipefail

# ── Colori ────────────────────────────────────────────────────────────────────
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${BLUE}[download]${NC} $*"; }
ok()    { echo -e "${GREEN}[download]${NC} ✅ $*"; }
warn()  { echo -e "${YELLOW}[download]${NC} ⚠️ $*"; }
error() { echo -e "${RED}[download]${NC} ❌ $*" >&2; exit 1; }

# ── Path ──────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="$SCRIPT_DIR/packer_cache"
PKRVARS="$SCRIPT_DIR/packer.pkrvars.hcl"

# ── Legge credenziali Proxmox dal pkrvars ─────────────────────────────────────
read_pkrvars() {
  local key="$1"
  grep -E "^\s*${key}\s*=" "$PKRVARS" | sed -E 's/.*"([^"]+)".*/\1/'
}

PROXMOX_URL=$(read_pkrvars proxmox_url)
PROXMOX_TOKEN_ID=$(read_pkrvars proxmox_token_id)
PROXMOX_TOKEN_SECRET=$(read_pkrvars proxmox_token_secret)
PROXMOX_NODE=$(read_pkrvars proxmox_node)
ISO_STORAGE=$(read_pkrvars iso_storage_pool)

[ -z "$PROXMOX_URL" ] && error "Impossibile leggere proxmox_url da $PKRVARS"
[ -z "$ISO_STORAGE" ] && error "Impossibile leggere iso_storage_pool da $PKRVARS"

AUTH_HEADER="Authorization: PVEAPIToken=${PROXMOX_TOKEN_ID}=${PROXMOX_TOKEN_SECRET}"

# ── Definizione ISO ───────────────────────────────────────────────────────────
declare -A ISO_NAMES ISO_URLS ISO_FILES ISO_SIZE

ISO_NAMES[ubuntu-22.04]="Ubuntu 22.04.5 LTS"
ISO_URLS[ubuntu-22.04]="https://releases.ubuntu.com/22.04/ubuntu-22.04.5-live-server-amd64.iso"
ISO_FILES[ubuntu-22.04]="ubuntu-22.04.5-live-server-amd64.iso"
ISO_SIZE[ubuntu-22.04]="~2.0GB"

ISO_NAMES[ubuntu-24.04]="Ubuntu 24.04.4 LTS"
ISO_URLS[ubuntu-24.04]="https://releases.ubuntu.com/24.04/ubuntu-24.04.4-live-server-amd64.iso"
ISO_FILES[ubuntu-24.04]="ubuntu-24.04.4-live-server-amd64.iso"
ISO_SIZE[ubuntu-24.04]="~3.2GB"

ISO_NAMES[rocky-9]="Rocky Linux 9.7 DVD"
ISO_URLS[rocky-9]="https://download.rockylinux.org/pub/rocky/9/isos/x86_64/Rocky-9.7-x86_64-dvd.iso"
ISO_FILES[rocky-9]="Rocky-9.7-x86_64-dvd.iso"
ISO_SIZE[rocky-9]="~12.4GB"

ISO_NAMES[debian-13]="Debian 13.5 Trixie"
ISO_URLS[debian-13]="https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-13.5.0-amd64-netinst.iso"
ISO_FILES[debian-13]="debian-13.5.0-amd64-netinst.iso"
ISO_SIZE[debian-13]="~755MB"

# ── Verifica se ISO esiste su Proxmox ─────────────────────────────────────────
iso_exists() {
  local filename="$1"
  local volid="${ISO_STORAGE}:iso/${filename}"
  local result
  result=$(curl -sk \
    -H "$AUTH_HEADER" \
    "${PROXMOX_URL}/nodes/${PROXMOX_NODE}/storage/${ISO_STORAGE}/content?content=iso" 2>/dev/null)
  echo "$result" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin).get('data', [])
    for d in data:
        if d.get('volid') == '$volid':
            sys.exit(0)
    sys.exit(1)
except:
    sys.exit(1)
" 2>/dev/null && return 0 || return 1
}

# ── Upload ISO su Proxmox ────────────────────────────────────────────────────
upload_iso() {
  local local_path="$1"
  local filename="$2"
  local task_upid

  info "Caricamento $filename su ${ISO_STORAGE}..."
  task_upid=$(curl -sk -X POST \
    -H "$AUTH_HEADER" \
    -F "content=iso" \
    -F "filename=@${local_path};filename=${filename}" \
    "${PROXMOX_URL}/nodes/${PROXMOX_NODE}/storage/${ISO_STORAGE}/upload" 2>/dev/null \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['data'])" 2>/dev/null)

  [ -z "$task_upid" ] && error "Fallito avvio upload ISO $filename"

  # Attesa completamento task
  local status exitstatus
  for i in $(seq 1 120); do
    sleep 5
    read -r status exitstatus < <(
      curl -sk "${PROXMOX_URL}/nodes/${PROXMOX_NODE}/tasks/${task_upid}/status" \
        -H "$AUTH_HEADER" 2>/dev/null \
        | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)['data']
    print(d['status'], d.get('exitstatus', ''))
except:
    print('unknown', '')
" 2>/dev/null
    )
    if [ "$status" = "stopped" ]; then
      [ "$exitstatus" = "OK" ] && return 0 || error "Upload $filename fallito: $exitstatus"
    fi
  done
  error "Timeout upload $filename"
}

# ── Scarica ISO con aria2c ────────────────────────────────────────────────────
download_iso() {
  local url="$1"
  local dest="$2"

  mkdir -p "$CACHE_DIR"
  info "Download $dest..."
  aria2c -x 16 -s 16 -k 1M --console-log-level=warn \
    -d "$CACHE_DIR" -o "$dest" "$url"
  ok "Download completato: $dest ($(du -h "$CACHE_DIR/$dest" | cut -f1))"
}
}

# ── Gestione ISO singola ──────────────────────────────────────────────────────
process_iso() {
  local key="$1"
  local clean="${2:-false}"
  local name="${ISO_NAMES[$key]}"
  local url="${ISO_URLS[$key]}"
  local filename="${ISO_FILES[$key]}"
  local size="${ISO_SIZE[$key]}"
  local local_path="$CACHE_DIR/$filename"

  echo ""
  info "━━━ $name ($size) ━━━"

  if iso_exists "$filename"; then
    ok "$filename già presente su $ISO_STORAGE"
    return 0
  fi

  warn "$filename non trovata su $ISO_STORAGE"

  if [ -f "$local_path" ]; then
    ok "$filename già presente in cache locale, salto download"
  else
    info "Download da: $url"
    download_iso "$url" "$filename"
  fi

  upload_iso "$local_path" "$filename"
  ok "$filename pronta su $ISO_STORAGE"

  if [ "$clean" = "true" ]; then
    rm -f "$local_path"
    ok "Cache locale rimossa: $filename"
  fi
}

# ── Menu interattivo ──────────────────────────────────────────────────────────
show_menu() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  DOWNLOAD ISO PER PACKER"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "Quale ISO scaricare/caricare su Proxmox?"
  echo "  1) Ubuntu 22.04 LTS    (~2.0GB)"
  echo "  2) Ubuntu 24.04 LTS    (~3.2GB)"
  echo "  3) Rocky Linux 9 DVD   (~12.4GB)"
  echo "  4) Debian 13 Trixie    (~755MB)"
  echo "  5) Tutte"
  echo ""
  read -rp "Seleziona (1-5): " choice
  echo ""

  case "$choice" in
    1) process_iso "ubuntu-22.04" "$CLEAN" ;;
    2) process_iso "ubuntu-24.04" "$CLEAN" ;;
    3) process_iso "rocky-9" "$CLEAN" ;;
    4) process_iso "debian-13" "$CLEAN" ;;
    5)
      process_iso "ubuntu-22.04" "$CLEAN"
      process_iso "ubuntu-24.04" "$CLEAN"
      process_iso "rocky-9" "$CLEAN"
      process_iso "debian-13" "$CLEAN"
      ;;
    *) error "Scelta non valida" ;;
  esac
}

# ── Main ──────────────────────────────────────────────────────────────────────
CLEAN=false
SELECTED=""

# Parsing argomenti CLI
while [ $# -gt 0 ]; do
  case "$1" in
    --clean) CLEAN=true; shift ;;
    rocky|rocky-9)     SELECTED="rocky-9"; shift ;;
    ubuntu-22.04|22.04) SELECTED="ubuntu-22.04"; shift ;;
    ubuntu-24.04|24.04) SELECTED="ubuntu-24.04"; shift ;;
    debian-13|13)      SELECTED="debian-13"; shift ;;
    all) SELECTED="all"; shift ;;
    *) error "Argomento sconosciuto: $1. Usa: rocky|ubuntu-22.04|ubuntu-24.04|debian-13|all|--clean" ;;
  esac
done

# Verifica packer.pkrvars.hcl
[ ! -f "$PKRVARS" ] && error "File $PKRVARS non trovato. Esegui prima init-project.sh"

case "$SELECTED" in
  rocky-9)       process_iso "rocky-9" "$CLEAN" ;;
  ubuntu-22.04)  process_iso "ubuntu-22.04" "$CLEAN" ;;
  ubuntu-24.04)  process_iso "ubuntu-24.04" "$CLEAN" ;;
  debian-13)     process_iso "debian-13" "$CLEAN" ;;
  all)
    process_iso "ubuntu-22.04" "$CLEAN"
    process_iso "ubuntu-24.04" "$CLEAN"
    process_iso "rocky-9" "$CLEAN"
    process_iso "debian-13" "$CLEAN"
    ;;
  *) show_menu ;;
esac

echo ""
ok "Operazione completata."
