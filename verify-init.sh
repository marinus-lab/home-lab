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

# Verifica storage pool in packer
grep -q "iso_storage_pool" "$SCRIPT_DIR/packer/packer.pkrvars.hcl" || \
  fail "packer/packer.pkrvars.hcl manca iso_storage_pool"
grep -q "iso_storage_pool.*PLACEHOLDER" "$SCRIPT_DIR/packer/packer.pkrvars.hcl" && \
  fail "packer/packer.pkrvars.hcl ha PLACEHOLDER non sostituito per iso_storage_pool"
pass "packer/packer.pkrvars.hcl contiene iso_storage_pool valido"

grep -q "template_storage_pool" "$SCRIPT_DIR/packer/packer.pkrvars.hcl" || \
  fail "packer/packer.pkrvars.hcl manca template_storage_pool"
grep -q "template_storage_pool.*PLACEHOLDER" "$SCRIPT_DIR/packer/packer.pkrvars.hcl" && \
  fail "packer/packer.pkrvars.hcl ha PLACEHOLDER non sostituito per template_storage_pool"
pass "packer/packer.pkrvars.hcl contiene template_storage_pool valido"

# Verifica terraform.tfvars
[ -f "$SCRIPT_DIR/terraform/terraform.tfvars" ] || fail "terraform/terraform.tfvars non esiste"
pass "terraform/terraform.tfvars esiste"

[ -f "$SCRIPT_DIR/terraform/terraform.auto.tfvars" ] || fail "terraform/terraform.auto.tfvars non esiste"
pass "terraform/terraform.auto.tfvars esiste"

grep -q "proxmox_token_secret = \"[a-f0-9\-]*\"" "$SCRIPT_DIR/terraform/terraform.auto.tfvars" || \
  fail "terraform/terraform.auto.tfvars token non valido o vuoto"
pass "terraform/terraform.auto.tfvars contiene token valido"

# Verifica parametri rete K8s in terraform.auto.tfvars
grep -q "k8s_subnet" "$SCRIPT_DIR/terraform/terraform.auto.tfvars" || \
  fail "terraform/terraform.auto.tfvars manca k8s_subnet"
pass "terraform/terraform.auto.tfvars contiene k8s_subnet"

grep -q "k8s_gateway" "$SCRIPT_DIR/terraform/terraform.auto.tfvars" || \
  fail "terraform/terraform.auto.tfvars manca k8s_gateway"
pass "terraform/terraform.auto.tfvars contiene k8s_gateway"

grep -q "master_ip_start" "$SCRIPT_DIR/terraform/terraform.auto.tfvars" || \
  fail "terraform/terraform.auto.tfvars manca master_ip_start"
pass "terraform/terraform.auto.tfvars contiene master_ip_start"

grep -q "worker_ip_start" "$SCRIPT_DIR/terraform/terraform.auto.tfvars" || \
  fail "terraform/terraform.auto.tfvars manca worker_ip_start"
pass "terraform/terraform.auto.tfvars contiene worker_ip_start"

# Verifica storage pool in terraform
grep -q "storage_pool" "$SCRIPT_DIR/terraform/terraform.auto.tfvars" || \
  fail "terraform/terraform.auto.tfvars manca storage_pool"
grep -q "storage_pool.*PLACEHOLDER" "$SCRIPT_DIR/terraform/terraform.auto.tfvars" && \
  fail "terraform/terraform.auto.tfvars ha PLACEHOLDER non sostituito per storage_pool"
pass "terraform/terraform.auto.tfvars contiene storage_pool valido"

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

# Estrai credenziali da terraform.auto.tfvars (file privato con credenziali)
PROXMOX_URL=$(grep "proxmox_url" "$SCRIPT_DIR/terraform/terraform.auto.tfvars" 2>/dev/null | grep -oP '(?<="https://)[^:]+')
PROXMOX_TOKEN_ID=$(grep "proxmox_token_id" "$SCRIPT_DIR/terraform/terraform.auto.tfvars" 2>/dev/null | grep -oP '(?<=")\K[^"]+')
PROXMOX_TOKEN_SECRET=$(grep "proxmox_token_secret" "$SCRIPT_DIR/terraform/terraform.auto.tfvars" 2>/dev/null | grep -oP '(?<=")\K[^"]+')
PROXMOX_NODE=$(grep "proxmox_node" "$SCRIPT_DIR/terraform/terraform.auto.tfvars" 2>/dev/null | grep -oP '(?<=")\K[^"]+')

[ -n "$PROXMOX_URL" ] || fail "terraform.auto.tfvars non trovato o URL Proxmox mancante"
pass "URL Proxmox: $PROXMOX_URL"

[ -n "$PROXMOX_TOKEN_ID" ] || fail "Token ID non trovato in terraform.auto.tfvars"
pass "Token ID: $PROXMOX_TOKEN_ID"

[ -n "$PROXMOX_TOKEN_SECRET" ] || fail "Token secret non trovato in terraform.auto.tfvars"
pass "Token secret presente"

[ -n "$PROXMOX_NODE" ] || fail "Nodo Proxmox non trovato in terraform.auto.tfvars"
pass "Nodo Proxmox: $PROXMOX_NODE"

# ── Test token API ────────────────────────────────────────────────────────────
# Estrai il nome utente dal token ID (prima del @)
AUTOMATION_USERNAME=$(echo "$PROXMOX_TOKEN_ID" | cut -d@ -f1)
pass "Utente automation: $AUTOMATION_USERNAME@pve"

# ── Test token ─────────────────────────────────────────────────────────────────
info "Test token API Proxmox..."

API_RESPONSE=$(curl -s -k -X GET \
  "https://$PROXMOX_URL:8006/api2/json/access/users/$AUTOMATION_USERNAME@pve/token" \
  -H "Authorization: PVEAPIToken=$PROXMOX_TOKEN_ID=$PROXMOX_TOKEN_SECRET" 2>&1 || echo '{"data":[]}')

if echo "$API_RESPONSE" | grep -q "\"data\""; then
  pass "Token API funzionante"
else
  fail "Token API non funzionante (secret sbagliato?)"
fi

# ───────────────────────────────────────────────────────────────────────────────
echo ""
echo "💾 STORAGE PROXMOX"
echo "───────────────────────────────────────────────────────────────────────────"

# Estrai storage pool dai file di configurazione
PACKER_ISO_POOL=$(grep "iso_storage_pool" "$SCRIPT_DIR/packer/packer.pkrvars.hcl" | grep -oP '"\K[^"]+' | head -1)
PACKER_TEMPLATE_POOL=$(grep "template_storage_pool" "$SCRIPT_DIR/packer/packer.pkrvars.hcl" | grep -oP '"\K[^"]+' | head -1)
TERRAFORM_STORAGE=$(grep "^storage_pool" "$SCRIPT_DIR/terraform/terraform.auto.tfvars" | grep -oP '"\K[^"]+' | head -1)

pass "Storage Packer ISO:       $PACKER_ISO_POOL"
pass "Storage Packer template:  $PACKER_TEMPLATE_POOL"
pass "Storage Terraform:        $TERRAFORM_STORAGE"

# Verifica che gli storage esistano realmente su Proxmox via API
info "Verifica esistenza storage su Proxmox..."

STORAGE_API_RESPONSE=$(curl -s -k -X GET \
  "https://$PROXMOX_URL:8006/api2/json/nodes/$PROXMOX_NODE/storage" \
  -H "Authorization: PVEAPIToken=$PROXMOX_TOKEN_ID=$PROXMOX_TOKEN_SECRET" 2>&1 || echo '{"data":[]}')

# Lista storage disponibili (|| true per evitare pipe failure con set -e)
AVAILABLE_STORAGES=$(echo "$STORAGE_API_RESPONSE" | grep -oP '"storage"\s*:\s*"\K[^"]+' | sort -u || true)

if [ -z "$AVAILABLE_STORAGES" ]; then
  warn "Impossibile recuperare lista storage da Proxmox (verifica permessi token)"
else
  # Verifica che PACKER_ISO_POOL esista
  if echo "$AVAILABLE_STORAGES" | grep -qx "$PACKER_ISO_POOL"; then
    pass "Storage ISO '$PACKER_ISO_POOL' esiste su Proxmox"
  else
    fail "Storage ISO '$PACKER_ISO_POOL' NON esiste su Proxmox. Disponibili: $(echo "$AVAILABLE_STORAGES" | tr '\n' ' ')"
  fi

  # Verifica che PACKER_TEMPLATE_POOL esista
  if echo "$AVAILABLE_STORAGES" | grep -qx "$PACKER_TEMPLATE_POOL"; then
    pass "Storage template '$PACKER_TEMPLATE_POOL' esiste su Proxmox"
  else
    fail "Storage template '$PACKER_TEMPLATE_POOL' NON esiste su Proxmox. Disponibili: $(echo "$AVAILABLE_STORAGES" | tr '\n' ' ')"
  fi

  # Verifica che TERRAFORM_STORAGE esista
  if echo "$AVAILABLE_STORAGES" | grep -qx "$TERRAFORM_STORAGE"; then
    pass "Storage Terraform '$TERRAFORM_STORAGE' esiste su Proxmox"
  else
    fail "Storage Terraform '$TERRAFORM_STORAGE' NON esiste su Proxmox. Disponibili: $(echo "$AVAILABLE_STORAGES" | tr '\n' ' ')"
  fi
fi

# ───────────────────────────────────────────────────────────────────────────────
echo ""
echo "📦 DIPENDENZE"
echo "───────────────────────────────────────────────────────────────────────────"

for cmd in curl ansible-vault terraform packer python3; do
  command -v "$cmd" >/dev/null || fail "$cmd non trovato"
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
