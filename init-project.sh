#!/usr/bin/env bash
# Inizializzazione progetto homelab — setup credenziali e configurazione
#
# Esecuzione:
#   bash init-project.sh
#
# Questo script:
# 1. Chiede le credenziali Proxmox (una sola volta)
# 2. Cifra tutto in Ansible Vault
# 3. Genera packer.pkrvars.hcl e terraform.tfvars
# 4. Crea l'utente API automation su Proxmox
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
command -v ansible >/dev/null || error "ansible non trovato — esegui setup-bastion.sh"
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

# ── Salva password Vault in file locale ───────────────────────────────────────
info "Salvataggio password Vault in $VAULT_PASS_FILE"
echo "$VAULT_PASSWORD" > "$VAULT_PASS_FILE"
chmod 600 "$VAULT_PASS_FILE"
ok "Password Vault salvata"

# ── Crea/aggiorna group_vars/all.yml con credenziali cifrate ──────────────────
info "Cifratura credenziali Ansible Vault..."

# Backup se esiste
if [ -f "$SCRIPT_DIR/group_vars/all.yml" ]; then
  cp "$SCRIPT_DIR/group_vars/all.yml" "$SCRIPT_DIR/group_vars/all.yml.bak"
  warn "Backup creato: group_vars/all.yml.bak"
fi

# Crea il file con le variabili cifrate
cat > "$SCRIPT_DIR/group_vars/all.yml" << EOF
---
# Credenziali Proxmox — CIFRATE CON ANSIBLE VAULT
# Per decifrare: ansible-vault view group_vars/all.yml --vault-password-file ~/.vault_pass
EOF

# Cifra vault_proxmox_root_pw
ENCRYPTED_ROOT=$(echo "$PROXMOX_ROOT_PW" | \
  ansible-vault encrypt_string --vault-password-file "$VAULT_PASS_FILE" \
  --name vault_proxmox_root_pw 2>/dev/null | grep -v "^\$ANSIBLE_VAULT")
echo "" >> "$SCRIPT_DIR/group_vars/all.yml"
echo "$ENCRYPTED_ROOT" >> "$SCRIPT_DIR/group_vars/all.yml"

# Cifra vault_automation_user_pw
ENCRYPTED_API=$(echo "$API_PASSWORD" | \
  ansible-vault encrypt_string --vault-password-file "$VAULT_PASS_FILE" \
  --name vault_automation_user_pw 2>/dev/null | grep -v "^\$ANSIBLE_VAULT")
echo "" >> "$SCRIPT_DIR/group_vars/all.yml"
echo "$ENCRYPTED_API" >> "$SCRIPT_DIR/group_vars/all.yml"

ok "Credenziali cifrate in group_vars/all.yml"

# ── Genera packer/packer.pkrvars.hcl ──────────────────────────────────────────
info "Generazione packer/packer.pkrvars.hcl..."

PACKER_VARS="$SCRIPT_DIR/packer/packer.pkrvars.hcl"
cat > "$PACKER_VARS" << 'EOF'
# Generato automaticamente da init-project.sh
# Contiene i dati di connessione a Proxmox per Packer

EOF

cat >> "$PACKER_VARS" << EOF
proxmox_url          = "https://$PROXMOX_HOST:8006/api2/json"
proxmox_token_id     = "$API_USERNAME@pve!packer"
proxmox_token_secret = "PLACEHOLDER_GENERATO_DA_ANSIBLE"
proxmox_node         = "pve"
storage_pool         = "local-lvm"
EOF

ok "packer/packer.pkrvars.hcl creato (token sarà riempito dopo)"

# ── Genera terraform/terraform.tfvars ─────────────────────────────────────────
info "Generazione terraform/terraform.tfvars..."

TERRAFORM_VARS="$SCRIPT_DIR/terraform/terraform.tfvars"
cat > "$TERRAFORM_VARS" << 'EOF'
# Generato automaticamente da init-project.sh
# Contiene i dati di connessione a Proxmox per Terraform

EOF

cat >> "$TERRAFORM_VARS" << EOF
proxmox_url          = "https://$PROXMOX_HOST:8006/api2/json"
proxmox_token_id     = "$API_USERNAME@pve!terraform"
proxmox_token_secret = "PLACEHOLDER_GENERATO_DA_ANSIBLE"

# Rete e VMs — adatta ai tuoi valori se necessario
proxmox_node = "pve"
k8s_subnet   = "192.168.1.0/24"
k8s_gateway  = "192.168.1.1"

control_plane_count = 1
worker_count        = 2
EOF

ok "terraform/terraform.tfvars creato (token sarà riempito dopo)"

# ── Installa collezioni Ansible ───────────────────────────────────────────────
info "Installazione collezioni Ansible..."
ansible-galaxy collection install -r "$SCRIPT_DIR/requirements.yml" >/dev/null 2>&1
ok "Collezioni Ansible installate"

# ── Crea l'utente API su Proxmox ──────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  CREAZIONE UTENTE API SU PROXMOX"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

info "Creazione utente $API_USERNAME@pve su $PROXMOX_HOST..."

# Esegui il playbook
ANSIBLE_VAULT_PASSWORD_FILE="$VAULT_PASS_FILE" \
ansible-playbook "$SCRIPT_DIR/create_proxmox_user.yml" \
  -e "proxmox_host=$PROXMOX_HOST" \
  -e "api_username=$API_USERNAME" \
  -e "api_token_id=packer" \
  --vault-password-file "$VAULT_PASS_FILE" 2>&1 | tee /tmp/ansible-output.log

# Estrai il token dal log di Ansible
TOKEN_VALUE=$(grep -oP "Value: \K[^ ]+" /tmp/ansible-output.log | head -1)

if [ -z "$TOKEN_VALUE" ]; then
  error "Token non generato — controlla il log sopra"
fi

ok "Utente API creato con successo"
echo ""
echo "Token generato:"
echo "  $TOKEN_VALUE"
echo ""

# ── Aggiorna i file .tfvars e .pkrvars con il token ──────────────────────────
info "Aggiornamento file di configurazione con il token..."

# Estrai solo il secret UUID dal token (parte dopo il =)
TOKEN_SECRET="${TOKEN_VALUE##*=}"

# Aggiorna packer.pkrvars.hcl
sed -i "s|proxmox_token_secret = \"PLACEHOLDER_GENERATO_DA_ANSIBLE\"|proxmox_token_secret = \"$TOKEN_SECRET\"|g" "$PACKER_VARS"

# Aggiorna terraform.tfvars
sed -i "s|proxmox_token_secret = \"PLACEHOLDER_GENERATO_DA_ANSIBLE\"|proxmox_token_secret = \"$TOKEN_SECRET\"|g" "$TERRAFORM_VARS"

ok "Token inserito nei file di configurazione"

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
echo "Per decifrare le credenziali:"
echo "  ansible-vault view group_vars/all.yml --vault-password-file ~/.vault_pass"
echo ""
