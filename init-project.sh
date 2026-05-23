#!/usr/bin/env bash
# Inizializzazione progetto homelab — setup credenziali e configurazione
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT_PASS_FILE="$HOME/.vault_pass"

# ── Colori ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[init]${NC} $*"; }
ok()    { echo -e "${GREEN}[init]${NC} ✅ $*"; }
warn()  { echo -e "${YELLOW}[init]${NC} ⚠️  $*"; }
error() { echo -e "${RED}[init]${NC} ❌ $*" >&2; exit 1; }

# ── Verifica prerequisiti ─────────────────────────────────────────────────────
info "Verifica prerequisiti..."
command -v curl >/dev/null || error "curl non trovato"
command -v ansible-vault >/dev/null || error "ansible-vault non trovato"
[ -f "$SCRIPT_DIR/requirements.yml" ] || error "requirements.yml non trovato"
ok "Prerequisiti OK"

# ── Input utente ──────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  INIZIALIZZAZIONE HOMELAB KUBERNETES"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Proxmox
read -rp "IP/hostname Proxmox (es. 192.168.1.10): " PROXMOX_HOST
[ -n "$PROXMOX_HOST" ] || error "IP Proxmox richiesto"

read -rsp "Password utente root@pam di Proxmox: " PROXMOX_ROOT_PW
echo ""
[ -n "$PROXMOX_ROOT_PW" ] || error "Password richiesta"

# Utente automation
read -rp "Nome utente automation (default: automation): " API_USERNAME
API_USERNAME="${API_USERNAME:-automation}"

# Leggi password API finché non è valida (min 8 caratteri)
while true; do
  read -rsp "Password per utente $API_USERNAME (min 8 caratteri): " API_PASSWORD
  echo ""

  if [ -z "$API_PASSWORD" ]; then
    warn "Password richiesta"
    continue
  fi

  if [ ${#API_PASSWORD} -lt 8 ]; then
    warn "Password troppo corta (${#API_PASSWORD} caratteri) — richiesti almeno 8 caratteri"
    continue
  fi

  ok "Password accettata (${#API_PASSWORD} caratteri)"
  break
done

# Vault (nessun vincolo di lunghezza)
read -rsp "Password per il Vault (proteggere bene!): " VAULT_PASSWORD
echo ""
[ -n "$VAULT_PASSWORD" ] || error "Password Vault richiesta"

# ── Salva password Vault ──────────────────────────────────────────────────────
info "Salvataggio password Vault in $VAULT_PASS_FILE"
echo "$VAULT_PASSWORD" > "$VAULT_PASS_FILE"
chmod 600 "$VAULT_PASS_FILE"
ok "Password Vault salvata"

# ── Crea group_vars/all.yml con credenziali cifrate ──────────────────────────
info "Cifratura credenziali Ansible Vault..."

if [ -f "$SCRIPT_DIR/group_vars/all.yml" ]; then
  cp "$SCRIPT_DIR/group_vars/all.yml" "$SCRIPT_DIR/group_vars/all.yml.bak"
  warn "Backup creato: group_vars/all.yml.bak"
fi

# Genera il file YAML con variabili cifrate
# Usa encrypt_string per ogni variabile e formatta il YAML manualmente
PROXMOX_ROOT_ENCRYPTED=$(echo "$PROXMOX_ROOT_PW" | \
  ansible-vault encrypt_string --vault-password-file "$VAULT_PASS_FILE" 2>/dev/null)

API_PASSWORD_ENCRYPTED=$(echo "$API_PASSWORD" | \
  ansible-vault encrypt_string --vault-password-file "$VAULT_PASS_FILE" 2>/dev/null)

cat > "$SCRIPT_DIR/group_vars/all.yml" << EOF
---
# Credenziali Proxmox — CIFRATE CON ANSIBLE VAULT
vault_proxmox_root_pw: $PROXMOX_ROOT_ENCRYPTED
vault_automation_user_pw: $API_PASSWORD_ENCRYPTED
EOF

ok "Credenziali cifrate in group_vars/all.yml"

# ── Genera packer/packer.pkrvars.hcl ──────────────────────────────────────────
info "Generazione packer/packer.pkrvars.hcl..."

cat > "$SCRIPT_DIR/packer/packer.pkrvars.hcl" << EOF
# Generato automaticamente da init-project.sh

proxmox_url          = "https://$PROXMOX_HOST:8006/api2/json"
proxmox_token_id     = "$API_USERNAME@pve!packer"
proxmox_token_secret = "PLACEHOLDER_GENERATO_DA_CURL"
proxmox_node         = "pve"
storage_pool         = "local-lvm"
EOF

ok "packer/packer.pkrvars.hcl creato"

# ── Genera terraform/terraform.auto.tfvars (credenziali) ────────────────────────
info "Generazione terraform/terraform.auto.tfvars..."

cat > "$SCRIPT_DIR/terraform/terraform.auto.tfvars" << EOF
# CREDENZIALI PROXMOX — Generato automaticamente da init-project.sh
# NON tracciato in git (.gitignore)

proxmox_url          = "https://$PROXMOX_HOST:8006/api2/json"
proxmox_token_id     = "$API_USERNAME@pve!terraform"
proxmox_token_secret = "PLACEHOLDER_GENERATO_DA_CURL"
EOF

ok "terraform/terraform.auto.tfvars creato (credenziali Proxmox)"
info "Configurazione cluster: modifica terraform/terraform.tfvars per topologia"

# ── Crea l'utente API su Proxmox con curl ─────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  CREAZIONE UTENTE API SU PROXMOX"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

info "Ottenimento ticket di sessione Proxmox..."

# Ottieni il ticket di sessione (richiesto per le operazioni API)
TICKET_RESPONSE=$(curl -s -k -X POST \
  "https://$PROXMOX_HOST:8006/api2/json/access/ticket" \
  -d "username=root@pam&password=$PROXMOX_ROOT_PW" 2>/dev/null || echo '{}')

TICKET=$(echo "$TICKET_RESPONSE" | grep -oP '"ticket"\s*:\s*"\K[^"]+' | head -1)
CSRF_TOKEN=$(echo "$TICKET_RESPONSE" | grep -oP '"CSRFPreventionToken"\s*:\s*"\K[^"]+' | head -1)

if [ -z "$TICKET" ]; then
  error "Impossibile ottenere ticket di sessione. Risposta: $TICKET_RESPONSE"
fi

ok "Ticket di sessione ottenuto"

info "Creazione utente $API_USERNAME@pve su $PROXMOX_HOST..."

# Crea l'utente usando il ticket (con verbose per il codice HTTP)
CURL_OUTPUT=$(curl -s -k -w "\n%{http_code}" -X POST \
  "https://$PROXMOX_HOST:8006/api2/json/access/users" \
  -b "PVEAuthCookie=$TICKET" \
  -H "CSRFPreventionToken: $CSRF_TOKEN" \
  -d "userid=$API_USERNAME@pve&password=$API_PASSWORD&comment=Automation%20user" 2>/dev/null)

CURL_RESPONSE=$(echo "$CURL_OUTPUT" | head -n -1)
HTTP_CODE=$(echo "$CURL_OUTPUT" | tail -n 1)

# Debug
echo "$CURL_RESPONSE" > /tmp/user_creation_debug.json

# Controlla il codice HTTP
if [ "$HTTP_CODE" = "200" ]; then
  ok "Utente $API_USERNAME@pve creato"
elif echo "$CURL_RESPONSE" | grep -q "already exists"; then
  warn "Utente $API_USERNAME@pve esiste già"
else
  error "Creazione utente fallita (HTTP $HTTP_CODE). Risposta: $CURL_RESPONSE"
fi

# Crea il token packer
info "Generazione token API per Packer..."

# Prova a creare il token (potrebbe già esistere)
TOKEN_RESPONSE=$(curl -s -k -w "\n%{http_code}" -X POST \
  "https://$PROXMOX_HOST:8006/api2/json/access/users/$API_USERNAME@pve/token/packer" \
  -b "PVEAuthCookie=$TICKET" \
  -H "CSRFPreventionToken: $CSRF_TOKEN" \
  -d "comment=Packer%20token" 2>/dev/null || echo -e '{}\n500')

TOKEN_BODY=$(echo "$TOKEN_RESPONSE" | head -n -1)
TOKEN_HTTP=$(echo "$TOKEN_RESPONSE" | tail -n 1)

if [ "$TOKEN_HTTP" = "400" ] && echo "$TOKEN_BODY" | grep -q "already exists"; then
  warn "Token packer esiste già — elimino e ricrei..."
  curl -s -k -X DELETE \
    "https://$PROXMOX_HOST:8006/api2/json/access/users/$API_USERNAME@pve/token/packer" \
    -b "PVEAuthCookie=$TICKET" \
    -H "CSRFPreventionToken: $CSRF_TOKEN" 2>/dev/null >/dev/null

  # Ricrea il token
  TOKEN_RESPONSE=$(curl -s -k -X POST \
    "https://$PROXMOX_HOST:8006/api2/json/access/users/$API_USERNAME@pve/token/packer" \
    -b "PVEAuthCookie=$TICKET" \
    -H "CSRFPreventionToken: $CSRF_TOKEN" \
    -d "comment=Packer%20token" 2>/dev/null || echo '{}')
  TOKEN_BODY="$TOKEN_RESPONSE"
fi

# Estrai il token dal JSON
TOKEN_SECRET=$(echo "$TOKEN_BODY" | grep -oP '"value"\s*:\s*"\K[^"]+' | head -1)

if [ -z "$TOKEN_SECRET" ]; then
  error "Token Packer non generato. Risposta: $TOKEN_BODY"
fi

ok "Token Packer creato"

# Crea il token terraform
info "Generazione token API per Terraform..."

# Prova a creare il token (potrebbe già esistere)
TERRAFORM_RESPONSE=$(curl -s -k -w "\n%{http_code}" -X POST \
  "https://$PROXMOX_HOST:8006/api2/json/access/users/$API_USERNAME@pve/token/terraform" \
  -b "PVEAuthCookie=$TICKET" \
  -H "CSRFPreventionToken: $CSRF_TOKEN" \
  -d "comment=Terraform%20token" 2>/dev/null || echo -e '{}\n500')

TERRAFORM_BODY=$(echo "$TERRAFORM_RESPONSE" | head -n -1)
TERRAFORM_HTTP=$(echo "$TERRAFORM_RESPONSE" | tail -n 1)

if [ "$TERRAFORM_HTTP" = "400" ] && echo "$TERRAFORM_BODY" | grep -q "already exists"; then
  warn "Token terraform esiste già — elimino e ricrei..."
  curl -s -k -X DELETE \
    "https://$PROXMOX_HOST:8006/api2/json/access/users/$API_USERNAME@pve/token/terraform" \
    -b "PVEAuthCookie=$TICKET" \
    -H "CSRFPreventionToken: $CSRF_TOKEN" 2>/dev/null >/dev/null

  # Ricrea il token
  TERRAFORM_RESPONSE=$(curl -s -k -X POST \
    "https://$PROXMOX_HOST:8006/api2/json/access/users/$API_USERNAME@pve/token/terraform" \
    -b "PVEAuthCookie=$TICKET" \
    -H "CSRFPreventionToken: $CSRF_TOKEN" \
    -d "comment=Terraform%20token" 2>/dev/null || echo '{}')
  TERRAFORM_BODY="$TERRAFORM_RESPONSE"
fi

# Estrai il token dal JSON
TERRAFORM_SECRET=$(echo "$TERRAFORM_BODY" | grep -oP '"value"\s*:\s*"\K[^"]+' | head -1)

if [ -z "$TERRAFORM_SECRET" ]; then
  warn "Token Terraform non generato — usa lo stesso di Packer"
  TERRAFORM_SECRET="$TOKEN_SECRET"
else
  ok "Token Terraform creato"
fi

# ── Aggiorna i file con i token ───────────────────────────────────────────────
info "Aggiornamento file di configurazione con i token..."

sed -i "s|proxmox_token_secret = \"PLACEHOLDER_GENERATO_DA_CURL\"|proxmox_token_secret = \"$TOKEN_SECRET\"|g" "$SCRIPT_DIR/packer/packer.pkrvars.hcl"
sed -i "s|proxmox_token_secret = \"PLACEHOLDER_GENERATO_DA_CURL\"|proxmox_token_secret = \"$TERRAFORM_SECRET\"|g" "$SCRIPT_DIR/terraform/terraform.auto.tfvars"

ok "Token inseriti nei file di configurazione"

# ── Riepilogo ─────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ INIZIALIZZAZIONE COMPLETATA"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "File creati/aggiornati:"
echo "  • group_vars/all.yml                    (credenziali Proxmox cifrate)"
echo "  • packer/packer.pkrvars.hcl             (token Packer)"
echo "  • terraform/terraform.auto.tfvars       (credenziali Terraform - privato)"
echo "  • terraform/terraform.tfvars            (configurazione cluster - pubblico)"
echo ""
echo "Credenziali Vault salvate in:"
echo "  • $VAULT_PASS_FILE                    (proteggere!)"
echo ""
echo "Prossimi passi:"
echo "  1. cd packer && ./build.sh              (crea template VM)"
echo "  2. cd ../terraform && terraform apply   (crea VM K8s)"
echo "  3. cd ../kubespray && ./deploy.sh       (installa Kubernetes)"
echo ""
