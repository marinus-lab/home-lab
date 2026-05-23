#!/usr/bin/env bash
# Script di verifica post-init-project.sh
# Controlla che init-project.sh abbia creato tutto correttamente
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
fail()  { echo -e "${RED}[❌]${NC} $*"; }
warn()  { echo -e "${YELLOW}[⚠️ ]${NC} $*"; }
info()  { echo -e "${BLUE}[ℹ️ ]${NC} $*"; }

CHECKS_PASSED=0
CHECKS_FAILED=0

# Helper per conteggio
check_pass() { ((CHECKS_PASSED++)); pass "$1"; }
check_fail() { ((CHECKS_FAILED++)); fail "$1"; }

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
if [ -f "$SCRIPT_DIR/packer/packer.pkrvars.hcl" ]; then
  check_pass "packer/packer.pkrvars.hcl esiste"

  if grep -q "proxmox_token_secret" "$SCRIPT_DIR/packer/packer.pkrvars.hcl"; then
    if grep "proxmox_token_secret = \"[a-f0-9\-]*\"" "$SCRIPT_DIR/packer/packer.pkrvars.hcl" >/dev/null; then
      check_pass "packer/packer.pkrvars.hcl contiene token valido"
    else
      check_fail "packer/packer.pkrvars.hcl token sembra vuoto o non valido"
    fi
  else
    check_fail "packer/packer.pkrvars.hcl manca token API"
  fi
else
  check_fail "packer/packer.pkrvars.hcl non esiste"
fi

# Verifica terraform.tfvars
if [ -f "$SCRIPT_DIR/terraform/terraform.tfvars" ]; then
  check_pass "terraform/terraform.tfvars esiste"

  if grep -q "proxmox_token_secret" "$SCRIPT_DIR/terraform/terraform.tfvars"; then
    if grep "proxmox_token_secret = \"[a-f0-9\-]*\"" "$SCRIPT_DIR/terraform/terraform.tfvars" >/dev/null; then
      check_pass "terraform/terraform.tfvars contiene token valido"
    else
      check_fail "terraform/terraform.tfvars token sembra vuoto o non valido"
    fi
  else
    check_fail "terraform/terraform.tfvars manca token API"
  fi
else
  check_fail "terraform/terraform.tfvars non esiste"
fi

# Verifica Vault
echo ""
echo "🔐 ANSIBLE VAULT"
echo "───────────────────────────────────────────────────────────────────────────"

if [ -f "$VAULT_PASS_FILE" ]; then
  check_pass "~/.vault_pass esiste"

  PERMS=$(stat -c "%a" "$VAULT_PASS_FILE" 2>/dev/null || stat -f "%OLp" "$VAULT_PASS_FILE" 2>/dev/null | tail -c 4)
  if [ "$PERMS" = "600" ] || [ "$PERMS" = "100600" ]; then
    check_pass "~/.vault_pass ha permessi corretti (600)"
  else
    warn "~/.vault_pass permessi: $PERMS (dovrebbe essere 600)"
  fi
else
  check_fail "~/.vault_pass non esiste"
fi

if [ -f "$SCRIPT_DIR/group_vars/all.yml" ]; then
  check_pass "group_vars/all.yml esiste"

  # Prova a decifrare
  if [ -f "$VAULT_PASS_FILE" ]; then
    if ansible-vault view "$SCRIPT_DIR/group_vars/all.yml" --vault-password-file "$VAULT_PASS_FILE" >/dev/null 2>&1; then
      check_pass "group_vars/all.yml è decifrabile"

      # Verifica che contiene le variabili
      VAULT_CONTENT=$(ansible-vault view "$SCRIPT_DIR/group_vars/all.yml" --vault-password-file "$VAULT_PASS_FILE")

      if echo "$VAULT_CONTENT" | grep -q "vault_proxmox_root_pw"; then
        check_pass "group_vars/all.yml contiene vault_proxmox_root_pw"
      else
        check_fail "group_vars/all.yml manca vault_proxmox_root_pw"
      fi

      if echo "$VAULT_CONTENT" | grep -q "vault_automation_user_pw"; then
        check_pass "group_vars/all.yml contiene vault_automation_user_pw"
      else
        check_fail "group_vars/all.yml manca vault_automation_user_pw"
      fi
    else
      check_fail "group_vars/all.yml non è decifrabile (password Vault sbagliata?)"
    fi
  else
    warn "Saltata verifica decrittazione (~/.vault_pass non esiste)"
  fi
else
  check_fail "group_vars/all.yml non esiste"
fi

# ───────────────────────────────────────────────────────────────────────────────
echo ""
echo "🔌 CONNESSIONE PROXMOX"
echo "───────────────────────────────────────────────────────────────────────────"

# Estrai i dati dai file .tfvars
PROXMOX_URL=$(grep "proxmox_url" "$SCRIPT_DIR/terraform/terraform.tfvars" 2>/dev/null | grep -oP '(?<="https://)[^:]*' || echo "")
PROXMOX_TOKEN_ID=$(grep "proxmox_token_id" "$SCRIPT_DIR/terraform/terraform.tfvars" 2>/dev/null | grep -oP '(?<=").*(?=@)' || echo "")

if [ -n "$PROXMOX_URL" ]; then
  check_pass "URL Proxmox estratto: $PROXMOX_URL"
else
  warn "Non riesco a estrarre URL Proxmox da terraform.tfvars"
fi

if [ -n "$PROXMOX_TOKEN_ID" ]; then
  check_pass "Token ID estratto: $PROXMOX_TOKEN_ID@pve"
else
  warn "Non riesco a estrarre Token ID da terraform.tfvars"
fi

# Testa la connessione a Proxmox (opzionale)
if [ -n "$PROXMOX_URL" ] && command -v curl >/dev/null; then
  echo ""
  read -rp "Testare la connessione a Proxmox? (s/n): " TEST_PROXMOX

  if [ "$TEST_PROXMOX" = "s" ] || [ "$TEST_PROXMOX" = "S" ]; then
    read -rsp "Password utente root@pam di Proxmox: " PROXMOX_ROOT_PW
    echo ""

    if curl -s -k "https://$PROXMOX_URL:8006/api2/json/nodes" \
      -u "root@pam:$PROXMOX_ROOT_PW" >/dev/null 2>&1; then
      check_pass "Connessione a Proxmox OK"

      # Testa il token
      if grep -q "proxmox_token_secret" "$SCRIPT_DIR/terraform/terraform.tfvars"; then
        TOKEN_SECRET=$(grep "proxmox_token_secret" "$SCRIPT_DIR/terraform/terraform.tfvars" | grep -oP '(?<=")\K[^"]+')

        if curl -s -k "https://$PROXMOX_URL:8006/api2/json/access/users" \
          -u "root@pam:$PROXMOX_ROOT_PW" \
          -X GET >/dev/null 2>&1; then
          check_pass "Token API funzionante"
        else
          warn "Token API non verificato (potrebbe essere ancora non attivo)"
        fi
      fi
    else
      check_fail "Connessione a Proxmox fallita (IP/password sbagliati?)"
    fi
  fi
fi

# ───────────────────────────────────────────────────────────────────────────────
echo ""
echo "📋 VERIFICA FILE VARI"
echo "───────────────────────────────────────────────────────────────────────────"

# Verifica che setup-bastion.sh esiste
if [ -f "$SCRIPT_DIR/setup-bastion.sh" ]; then
  check_pass "setup-bastion.sh esiste"
else
  check_fail "setup-bastion.sh non trovato"
fi

# Verifica che packer/build.sh esiste ed è eseguibile
if [ -x "$SCRIPT_DIR/packer/build.sh" ]; then
  check_pass "packer/build.sh esiste ed è eseguibile"
else
  check_fail "packer/build.sh non trovato o non eseguibile"
fi

# Verifica che kubespray/deploy.sh esiste ed è eseguibile
if [ -x "$SCRIPT_DIR/kubespray/deploy.sh" ]; then
  check_pass "kubespray/deploy.sh esiste ed è eseguibile"
else
  check_fail "kubespray/deploy.sh non trovato o non eseguibile"
fi

# ───────────────────────────────────────────────────────────────────────────────
echo ""
echo "📦 DIPENDENZE"
echo "───────────────────────────────────────────────────────────────────────────"

for cmd in curl ansible-vault terraform packer; do
  if command -v "$cmd" >/dev/null; then
    VERSION=$($cmd --version 2>&1 | head -1)
    check_pass "$cmd disponibile: $VERSION"
  else
    check_fail "$cmd non trovato — esegui setup-bastion.sh"
  fi
done

# ───────────────────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  RIEPILOGO"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

TOTAL=$((CHECKS_PASSED + CHECKS_FAILED))
PERCENTAGE=$((CHECKS_PASSED * 100 / TOTAL))

echo "Verifiche: $CHECKS_PASSED/$TOTAL passate ($PERCENTAGE%)"
echo ""

if [ $CHECKS_FAILED -eq 0 ]; then
  echo -e "${GREEN}✅ TUTTO OK — pronto per deploy!${NC}"
  echo ""
  echo "Prossimi passi:"
  echo "  1. cd packer && ./build.sh        (crea template VM)"
  echo "  2. cd ../terraform && terraform apply  (crea VM K8s)"
  echo "  3. cd ../kubespray && ./deploy.sh      (installa Kubernetes)"
  exit 0
else
  echo -e "${RED}❌ $CHECKS_FAILED verifiche fallite${NC}"
  echo ""
  echo "Correggi gli errori sopra e riesegui questo script:"
  echo "  bash verify-init.sh"
  exit 1
fi
