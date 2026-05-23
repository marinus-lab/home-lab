#!/usr/bin/env bash
# Script di verifica post-init-project.sh
# Controlla che init-project.sh abbia creato tutto correttamente
# e che le credenziali siano funzionanti
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT_PASS_FILE="$HOME/.vault_pass"

# ── Colori ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

pass()  { echo -e "${GREEN}[✅]${NC} $*"; }
fail()  { echo -e "${RED}[❌]${NC} $*"; exit 1; }
warn()  { echo -e "${YELLOW}[⚠️ ]${NC} $*"; }
info()  { echo -e "${BLUE}[ℹ️ ]${NC} $*"; }

# ── Header ────────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  VERIFICA CONFIGURAZIONE HOMELAB"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ───────────────────────────────────────────────────────────────────────────────
echo "📁 FILE DI CONFIGURAZIONE"
echo "───────────────────────────────────────────────────────────────────────────"

# Verifica packer.pkrvars.hcl
[ -f "$SCRIPT_DIR/packer/packer.pkrvars.hcl" ] || fail "packer/packer.pkrvars.hcl non esiste"
pass "packer/packer.pkrvars.hcl esiste"

grep -q "proxmox_token_secret = \"[a-f0-9\-]*\"" "$SCRIPT_DIR/packer/packer.pkrvars.hcl" || \
  fail "packer/packer.pkrvars.hcl token non valido o vuoto"
pass "packer/packer.pkrvars.hcl contiene token valido"

# Verifica terraform.tfvars
[ -f "$SCRIPT_DIR/terraform/terraform.tfvars" ] || fail "terraform/terraform.tfvars non esiste"
pass "terraform/terraform.tfvars esiste"

grep -q "proxmox_token_secret = \"[a-f0-9\-]*\"" "$SCRIPT_DIR/terraform/terraform.tfvars" || \
  fail "terraform/terraform.tfvars token non valido o vuoto"
pass "terraform/terraform.tfvars contiene token valido"

# ───────────────────────────────────────────────────────────────────────────────
echo ""
echo "🔐 ANSIBLE VAULT"
echo "───────────────────────────────────────────────────────────────────────────"

[ -f "$VAULT_PASS_FILE" ] || fail "~/.vault_pass non esiste"
pass "~/.vault_pass esiste"

# Verifica permessi
PERMS=$(stat -c "%a" "$VAULT_PASS_FILE" 2>/dev/null || stat -f "%OLp" "$VAULT_PASS_FILE" 2>/dev/null | tail -c 4)
[ "$PERMS" = "600" ] || [ "$PERMS" = "100600" ] || \
  fail "~/.vault_pass permessi sbagliati: $PERMS (deve essere 600)"
pass "~/.vault_pass ha permessi corretti (600)"

[ -f "$SCRIPT_DIR/group_vars/all.yml" ] || fail "group_vars/all.yml non esiste"
pass "group_vars/all.yml esiste"

# Verifica che il file contiene variabili Vault cifrate
grep -q "!vault" "$SCRIPT_DIR/group_vars/all.yml" || fail "group_vars/all.yml non contiene credenziali cifrate"
pass "group_vars/all.yml contiene credenziali cifrate"

# Verifica che le variabili attese sono presenti nel file
grep -q "vault_proxmox_root_pw:" "$SCRIPT_DIR/group_vars/all.yml" || fail "vault_proxmox_root_pw non trovata"
pass "vault_proxmox_root_pw presente"

grep -q "vault_automation_user_pw:" "$SCRIPT_DIR/group_vars/all.yml" || fail "vault_automation_user_pw non trovata"
pass "vault_automation_user_pw presente"

# ───────────────────────────────────────────────────────────────────────────────
echo ""
echo "🔌 CONNESSIONE PROXMOX"
echo "───────────────────────────────────────────────────────────────────────────"

# Estrai i dati dai file .tfvars
PROXMOX_URL=$(grep "proxmox_url" "$SCRIPT_DIR/terraform/terraform.tfvars" | grep -oP '(?<="https://)[^:]+')
PROXMOX_TOKEN_ID=$(grep "proxmox_token_id" "$SCRIPT_DIR/terraform/terraform.tfvars" | grep -oP '(?<=")\K[^"]+')
PROXMOX_TOKEN_SECRET=$(grep "proxmox_token_secret" "$SCRIPT_DIR/terraform/terraform.tfvars" | grep -oP '(?<=")\K[^"]+')

[ -n "$PROXMOX_URL" ] || fail "URL Proxmox non trovato in terraform.tfvars"
pass "URL Proxmox: $PROXMOX_URL"

[ -n "$PROXMOX_TOKEN_ID" ] || fail "Token ID non trovato in terraform.tfvars"
pass "Token ID: $PROXMOX_TOKEN_ID"

[ -n "$PROXMOX_TOKEN_SECRET" ] || fail "Token secret non trovato in terraform.tfvars"
pass "Token secret presente"

# ── Test token API ────────────────────────────────────────────────────────────
# Estrai il nome utente dal token ID (prima del @)
AUTOMATION_USERNAME=$(echo "$PROXMOX_TOKEN_ID" | cut -d@ -f1)
pass "Utente automation: $AUTOMATION_USERNAME@pve"

# ── Test token ─────────────────────────────────────────────────────────────────
info "Test token API Proxmox..."

API_RESPONSE=$(curl -s -k -X GET \
  "https://$PROXMOX_URL:8006/api2/json/access/users/$AUTOMATION_USERNAME@pve/token" \
  -u "$PROXMOX_TOKEN_ID:$PROXMOX_TOKEN_SECRET" 2>&1 || echo '{"data":[]}')

if echo "$API_RESPONSE" | grep -q "\"data\""; then
  pass "Token API funzionante"
else
  fail "Token API non funzionante (secret sbagliato?)"
fi

# ───────────────────────────────────────────────────────────────────────────────
echo ""
echo "📦 DIPENDENZE"
echo "───────────────────────────────────────────────────────────────────────────"

for cmd in curl ansible-vault terraform packer; do
  command -v "$cmd" >/dev/null || fail "$cmd non trovato"
  VERSION=$($cmd --version 2>&1 | head -1 | cut -d' ' -f1-3)
  pass "$cmd disponibile"
done

# ───────────────────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ TUTTE LE VERIFICHE PASSATE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Prossimi passi:"
echo "  1. cd packer && ./build.sh              (crea template VM)"
echo "  2. cd ../terraform && terraform apply   (crea VM K8s)"
echo "  3. cd ../kubespray && ./deploy.sh       (installa Kubernetes)"
echo ""
