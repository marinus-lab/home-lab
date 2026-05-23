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

read -rsp "Password per utente $API_USERNAME: " API_PASSWORD
echo ""
[ -n "$API_PASSWORD" ] || error "Password richiesta"

# Vault
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

cat > "$SCRIPT_DIR/group_vars/all.yml" << EOF
---
# Credenziali Proxmox — CIFRATE CON ANSIBLE VAULT
EOF

# Cifra vault_proxmox_root_pw
echo "$PROXMOX_ROOT_PW" | \
  ansible-vault encrypt_string --vault-password-file "$VAULT_PASS_FILE" \
  --name vault_proxmox_root_pw >> "$SCRIPT_DIR/group_vars/all.yml" 2>/dev/null

# Cifra vault_automation_user_pw
echo "$API_PASSWORD" | \
  ansible-vault encrypt_string --vault-password-file "$VAULT_PASS_FILE" \
  --name vault_automation_user_pw >> "$SCRIPT_DIR/group_vars/all.yml" 2>/dev/null

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

# ── Genera terraform/terraform.tfvars ─────────────────────────────────────────
info "Generazione terraform/terraform.tfvars..."

cat > "$SCRIPT_DIR/terraform/terraform.tfvars" << EOF
# Generato automaticamente da init-project.sh

proxmox_url          = "https://$PROXMOX_HOST:8006/api2/json"
proxmox_token_id     = "$API_USERNAME@pve!terraform"
proxmox_token_secret = "PLACEHOLDER_GENERATO_DA_CURL"

proxmox_node = "pve"
k8s_subnet   = "192.168.1.0/24"
k8s_gateway  = "192.168.1.1"

control_plane_count = 1
worker_count        = 2
EOF

ok "terraform/terraform.tfvars creato"

# ── Crea l'utente API su Proxmox con curl ─────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  CREAZIONE UTENTE API SU PROXMOX"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

info "Creazione utente $API_USERNAME@pve su $PROXMOX_HOST..."

# Crea l'utente
CURL_RESPONSE=$(curl -s -k -X POST \
  "https://$PROXMOX_HOST:8006/api2/json/access/users" \
  -u "root@pam:$PROXMOX_ROOT_PW" \
  -d "userid=$API_USERNAME@pve&password=$API_PASSWORD&comment=Automation%20user" 2>/dev/null || echo '{}')

# Ignora se l'utente esiste già
if echo "$CURL_RESPONSE" | grep -q "already exists"; then
  warn "Utente $API_USERNAME@pve esiste già"
elif echo "$CURL_RESPONSE" | grep -q "\"data\""; then
  ok "Utente $API_USERNAME@pve creato"
fi

# Crea il token packer
info "Generazione token API per Packer..."

TOKEN_RESPONSE=$(curl -s -k -X POST \
  "https://$PROXMOX_HOST:8006/api2/json/access/users/$API_USERNAME@pve/token/packer" \
  -u "root@pam:$PROXMOX_ROOT_PW" \
  -d "comment=Packer%20token" 2>/dev/null || echo '{}')

TOKEN_SECRET=$(echo "$TOKEN_RESPONSE" | grep -oP '"value":"?\K[^"]+' | head -1)

if [ -z "$TOKEN_SECRET" ]; then
  error "Token non generato. Risposta: $TOKEN_RESPONSE"
fi

ok "Token Packer creato"
echo "Token: $API_USERNAME@pve!packer=$TOKEN_SECRET"

# Crea il token terraform
info "Generazione token API per Terraform..."

TERRAFORM_TOKEN=$(curl -s -k -X POST \
  "https://$PROXMOX_HOST:8006/api2/json/access/users/$API_USERNAME@pve/token/terraform" \
  -u "root@pam:$PROXMOX_ROOT_PW" \
  -d "comment=Terraform%20token" 2>/dev/null || echo '{}')

TERRAFORM_SECRET=$(echo "$TERRAFORM_TOKEN" | grep -oP '"value":"?\K[^"]+' | head -1)

if [ -z "$TERRAFORM_SECRET" ]; then
  warn "Token Terraform non generato — usa lo stesso di Packer"
  TERRAFORM_SECRET="$TOKEN_SECRET"
else
  ok "Token Terraform creato"
fi

# ── Aggiorna i file con i token ───────────────────────────────────────────────
info "Aggiornamento file di configurazione con i token..."

sed -i "s|proxmox_token_secret = \"PLACEHOLDER_GENERATO_DA_CURL\"|proxmox_token_secret = \"$TOKEN_SECRET\"|g" "$SCRIPT_DIR/packer/packer.pkrvars.hcl"
sed -i "s|proxmox_token_secret = \"PLACEHOLDER_GENERATO_DA_CURL\"|proxmox_token_secret = \"$TERRAFORM_SECRET\"|g" "$SCRIPT_DIR/terraform/terraform.tfvars"

ok "Token inseriti nei file di configurazione"

# ── Riepilogo ─────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ INIZIALIZZAZIONE COMPLETATA"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "File creati/aggiornati:"
echo "  • group_vars/all.yml                    (credenziali cifrate)"
echo "  • packer/packer.pkrvars.hcl             (configurazione Packer)"
echo "  • terraform/terraform.tfvars            (configurazione Terraform)"
echo ""
echo "Credenziali Vault salvate in:"
echo "  • $VAULT_PASS_FILE                    (proteggere!)"
echo ""
echo "Prossimi passi:"
echo "  1. cd packer && ./build.sh              (crea template VM)"
echo "  2. cd ../terraform && terraform apply   (crea VM K8s)"
echo "  3. cd ../kubespray && ./deploy.sh       (installa Kubernetes)"
echo ""
