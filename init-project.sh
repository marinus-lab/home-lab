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

# ── PROXMOX ────────────────────────────────────────────────────────────────────
echo "🔌 CREDENZIALI PROXMOX"
echo ""

# IP/hostname Proxmox
while true; do
  read -rp "IP/hostname Proxmox (es. 192.168.1.10): " PROXMOX_HOST
  echo ""

  if [ -z "$PROXMOX_HOST" ]; then
    warn "IP/hostname Proxmox richiesto"
    continue
  fi

  ok "Proxmox host: $PROXMOX_HOST"
  break
done

# Password root Proxmox
while true; do
  read -rsp "Password utente root@pam di Proxmox: " PROXMOX_ROOT_PW
  echo ""

  if [ -z "$PROXMOX_ROOT_PW" ]; then
    warn "Password Proxmox richiesta"
    echo ""
    continue
  fi

  ok "Password Proxmox accettata"
  break
done

# ── UTENTE AUTOMATION ──────────────────────────────────────────────────────────
echo ""
echo "👤 UTENTE AUTOMATION"
echo ""
read -rp "Nome utente automation (default: automation): " API_USERNAME
API_USERNAME="${API_USERNAME:-automation}"

# ── PASSWORD API USER ──────────────────────────────────────────────────────────
echo ""
echo "🔐 PASSWORD UTENTE AUTOMATION"
echo ""
# Leggi password API finché non è valida (min 8 caratteri)
while true; do
  read -rsp "Password per utente $API_USERNAME (min 8 caratteri): " API_PASSWORD
  echo ""

  if [ -z "$API_PASSWORD" ]; then
    warn "Password richiesta"
    echo ""
    continue
  fi

  if [ ${#API_PASSWORD} -lt 8 ]; then
    warn "Password troppo corta (${#API_PASSWORD} caratteri) — richiesti almeno 8 caratteri"
    echo ""
    continue
  fi

  ok "Password accettata (${#API_PASSWORD} caratteri)"
  break
done

# ── RETE KUBERNETES ───────────────────────────────────────────────────────────
echo ""
echo "🌐 RETE KUBERNETES"
echo ""

# Subnet Kubernetes
while true; do
  read -rp "Subnet Kubernetes (es. 192.168.0.0/24): " K8S_SUBNET
  echo ""

  if [ -z "$K8S_SUBNET" ]; then
    warn "Subnet Kubernetes richiesta"
    continue
  fi

  if ! echo "$K8S_SUBNET" | grep -qE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$'; then
    warn "Formato subnet non valido (usa CIDR, es. 192.168.0.0/24)"
    echo ""
    continue
  fi

  ok "Subnet Kubernetes: $K8S_SUBNET"
  break
done

# Gateway Kubernetes
while true; do
  echo ""
  read -rp "Gateway Kubernetes (es. 192.168.0.1): " K8S_GATEWAY
  echo ""

  if [ -z "$K8S_GATEWAY" ]; then
    warn "Gateway Kubernetes richiesto"
    continue
  fi

  if ! echo "$K8S_GATEWAY" | grep -qE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'; then
    warn "Formato gateway non valido (usa formato IP, es. 192.168.0.1)"
    echo ""
    continue
  fi

  ok "Gateway Kubernetes: $K8S_GATEWAY"
  break
done

# Ultimo ottetto IP primo master
while true; do
  echo ""
  read -rp "Ultimo ottetto IP primo master (es. 210): " MASTER_IP_OCTET
  echo ""

  if [ -z "$MASTER_IP_OCTET" ]; then
    warn "Ultimo ottetto master richiesto"
    continue
  fi

  if ! echo "$MASTER_IP_OCTET" | grep -qE '^[0-9]{1,3}$' || [ "$MASTER_IP_OCTET" -lt 0 ] || [ "$MASTER_IP_OCTET" -gt 253 ]; then
    warn "Ottetto non valido (deve essere un numero tra 0 e 253)"
    echo ""
    continue
  fi

  ok "IP primo master: ultimo ottetto $MASTER_IP_OCTET"
  break
done

# Ultimo ottetto IP primo worker
while true; do
  echo ""
  read -rp "Ultimo ottetto IP primo worker (es. 220): " WORKER_IP_OCTET
  echo ""

  if [ -z "$WORKER_IP_OCTET" ]; then
    warn "Ultimo ottetto worker richiesto"
    continue
  fi

  if ! echo "$WORKER_IP_OCTET" | grep -qE '^[0-9]{1,3}$' || [ "$WORKER_IP_OCTET" -lt 0 ] || [ "$WORKER_IP_OCTET" -gt 253 ]; then
    warn "Ottetto non valido (deve essere un numero tra 0 e 253)"
    echo ""
    continue
  fi

  # Verifica che worker IP non sia troppo vicino a master IP
  if [ "$WORKER_IP_OCTET" -le "$((MASTER_IP_OCTET + 2))" ]; then
    warn "Ultimo ottetto worker deve essere > $((MASTER_IP_OCTET + 2)) per evitare conflitti con master"
    echo ""
    continue
  fi

  ok "IP primo worker: ultimo ottetto $WORKER_IP_OCTET"
  break
done

ok "Rete Kubernetes configurata"

# ── VAULT PASSWORD ────────────────────────────────────────────────────────────
echo ""
echo "🔐 PASSWORD VAULT"
echo ""

while true; do
  read -rsp "Password per il Vault (proteggere bene!): " VAULT_PASSWORD
  echo ""

  if [ -z "$VAULT_PASSWORD" ]; then
    warn "Password Vault richiesta"
    echo ""
    continue
  fi

  ok "Password Vault accettata"
  break
done

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
proxmox_node         = "PLACEHOLDER_NODO"
storage_pool         = "local-lvm"
EOF

ok "packer/packer.pkrvars.hcl creato"

# ── Genera terraform/terraform.auto.tfvars (credenziali) ────────────────────────
info "Generazione terraform/terraform.auto.tfvars..."

cat > "$SCRIPT_DIR/terraform/terraform.auto.tfvars" << EOF
# CREDENZIALI E CONFIGURAZIONE RETE — Generato automaticamente da init-project.sh
# NON tracciato in git (.gitignore)

# ── Credenziali Proxmox ────────────────────────────────────────────────────────
proxmox_url          = "https://$PROXMOX_HOST:8006/api2/json"
proxmox_token_id     = "$API_USERNAME@pve!terraform"
proxmox_token_secret = "PLACEHOLDER_GENERATO_DA_CURL"
proxmox_node         = "PLACEHOLDER_NODO"

# ── Rete Kubernetes ────────────────────────────────────────────────────────────
k8s_subnet      = "$K8S_SUBNET"
k8s_gateway     = "$K8S_GATEWAY"
master_ip_start = $MASTER_IP_OCTET
worker_ip_start = $WORKER_IP_OCTET
EOF

ok "terraform/terraform.auto.tfvars creato (credenziali + rete Kubernetes)"

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

# ── Rileva il nodo Proxmox disponibile ─────────────────────────────────────────
info "Rilevamento nodo Proxmox..."

NODES_RESPONSE=$(curl -s -k -X GET \
  "https://$PROXMOX_HOST:8006/api2/json/nodes" \
  -b "PVEAuthCookie=$TICKET" \
  -H "CSRFPreventionToken: $CSRF_TOKEN" 2>/dev/null)

# Estrai lista nodi dal JSON (prova con grep per robustezza)
NODES_LIST=$(echo "$NODES_RESPONSE" | grep -oP '"node"\s*:\s*"\K[^"]+' | sort -u)

# Conta nodi
NODES_COUNT=$(echo "$NODES_LIST" | wc -l)

if [ -z "$NODES_LIST" ]; then
  error "Nessun nodo trovato in Proxmox. Risposta: $NODES_RESPONSE"
fi

if [ "$NODES_COUNT" -eq 1 ]; then
  PROXMOX_NODE=$(echo "$NODES_LIST" | head -1)
  ok "Nodo Proxmox rilevato: $PROXMOX_NODE"
else
  # Più nodi — chiedi all'utente
  warn "Trovati $NODES_COUNT nodi Proxmox:"
  echo ""
  echo "Nodi disponibili:"
  echo "$NODES_LIST" | nl
  echo ""
  read -rp "Seleziona il numero del nodo da usare: " NODE_NUM
  PROXMOX_NODE=$(echo "$NODES_LIST" | sed -n "${NODE_NUM}p")

  if [ -z "$PROXMOX_NODE" ]; then
    error "Selezione nodo non valida"
  fi
  ok "Nodo selezionato: $PROXMOX_NODE"
fi

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

# ── Aggiorna i file con i token e il nodo ────────────────────────────────────
info "Aggiornamento file di configurazione con i token e nodo Proxmox..."

# Aggiorna token e nodo in packer
sed -i "s|proxmox_token_secret = \"PLACEHOLDER_GENERATO_DA_CURL\"|proxmox_token_secret = \"$TOKEN_SECRET\"|g" "$SCRIPT_DIR/packer/packer.pkrvars.hcl"
sed -i "s|proxmox_node = \"PLACEHOLDER_NODO\"|proxmox_node = \"$PROXMOX_NODE\"|g" "$SCRIPT_DIR/packer/packer.pkrvars.hcl"

# Aggiorna token e nodo in terraform
sed -i "s|proxmox_token_secret = \"PLACEHOLDER_GENERATO_DA_CURL\"|proxmox_token_secret = \"$TERRAFORM_SECRET\"|g" "$SCRIPT_DIR/terraform/terraform.auto.tfvars"
sed -i "s|proxmox_node = \"PLACEHOLDER_NODO\"|proxmox_node = \"$PROXMOX_NODE\"|g" "$SCRIPT_DIR/terraform/terraform.auto.tfvars"

ok "Token e nodo Proxmox inseriti nei file di configurazione"

# ── Riepilogo ─────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ INIZIALIZZAZIONE COMPLETATA"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "File creati/aggiornati:"
echo "  • group_vars/all.yml                    (credenziali Proxmox cifrate)"
echo "  • packer/packer.pkrvars.hcl             (token Packer)"
echo "  • terraform/terraform.auto.tfvars       (credenziali + rete Kubernetes)"
echo "  • terraform/terraform.tfvars            (topologia cluster - pubblico)"
echo ""
echo "Configurazione Kubernetes:"
echo "  • Subnet: $K8S_SUBNET"
echo "  • Gateway: $K8S_GATEWAY"
echo "  • Master IP: $MASTER_IP_OCTET-$((MASTER_IP_OCTET+2))"
echo "  • Worker IP: $WORKER_IP_OCTET-$((WORKER_IP_OCTET+2))"
echo ""
echo "Credenziali Vault salvate in:"
echo "  • $VAULT_PASS_FILE                    (proteggere!)"
echo ""
echo "Prossimi passi:"
echo "  1. (Opzionale) Modifica topologia: vim terraform/terraform.tfvars"
echo "  2. cd packer && ./build.sh              (crea template VM)"
echo "  3. cd ../terraform && terraform apply   (crea VM K8s)"
echo "  4. cd ../kubespray && ./deploy.sh       (installa Kubernetes)"
echo ""
