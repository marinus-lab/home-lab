#!/usr/bin/env bash
# Configura un provider LLM custom OpenAI-compatible su
# OpenCode, Hermes Agent e Pi Agent (solo se installati).
#
# Uso:
#   bash configure-ai-agents.sh
#   CUSTOM_OPENAI_URL=https://api.example.com/v1 \
#   CUSTOM_OPENAI_API_KEY=sk-... \
#   CUSTOM_OPENAI_MODEL=gpt-4o \
#   bash configure-ai-agents.sh
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[agents]${NC} $*"; }
ok()    { echo -e "${GREEN}[agents]${NC} $*"; }
warn()  { echo -e "${YELLOW}[agents]${NC} $*"; }
error() { echo -e "${RED}[agents]${NC} $*">&2; exit 1; }

PROVIDER_ID="custom-openai"
PROVIDER_NAME="Custom OpenAI"
ENV_KEY="CUSTOM_OPENAI_API_KEY"
ENV_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/homelab/custom-openai.env"

export PATH="$HOME/.opencode/bin:$HOME/.local/bin:$HOME/.pi/agent/bin:$HOME/.npm-global/bin:$PATH"

# ── Lookup binari ─────────────────────────────────────────────────────────────
find_bin() {
  local name="$1" p
  if command -v "$name" >/dev/null 2>&1; then
    command -v "$name"
    return 0
  fi
  for p in \
    "$HOME/.local/bin/$name" \
    "$HOME/.opencode/bin/$name" \
    "$HOME/.pi/agent/bin/$name" \
    "$HOME/.npm-global/bin/$name" \
    "/usr/local/bin/$name" \
    "/usr/bin/$name"
  do
    if [ -x "$p" ]; then
      echo "$p"
      return 0
    fi
  done
  return 1
}

OPENCODE_BIN="$(find_bin opencode || true)"
HERMES_BIN="$(find_bin hermes || true)"
PI_BIN="$(find_bin pi || true)"

# ── Prompt ────────────────────────────────────────────────────────────────────
prompt() {
  local var="$1" label="$2" silent="${3:-0}" value=""
  if [ -n "${!var:-}" ]; then
    return 0
  fi
  if [ ! -t 0 ] && [ ! -r /dev/tty ]; then
    error "Manca $var e non c'è un TTY. Esporta $var e rilancia."
  fi
  if [ "$silent" = "1" ]; then
    read -r -s -p "$label" value </dev/tty
    echo "" >/dev/tty
  else
    read -r -p "$label" value </dev/tty
  fi
  printf -v "$var" '%s' "$value"
}

normalize_url() {
  local url="$1"
  url="${url#"${url%%[![:space:]]*}"}"
  url="${url%"${url##*[![:space:]]}"}"
  url="${url%/}"
  case "$url" in
    http://*|https://*) ;;
    *) url="https://$url" ;;
  esac
  case "$url" in
    */v1) ;;
    *) url="$url/v1" ;;
  esac
  printf '%s' "$url"
}

upsert_env_file() {
  local file="$1"
  mkdir -p "$(dirname "$file")"
  touch "$file"
  chmod 600 "$file"
  /usr/bin/python3 - "$file" "$ENV_KEY" "$BASE_URL" "$MODEL" <<'PY'
import os, sys
path, key, url, model = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
value = os.environ.get(key, "")
wanted = {
    key: value,
    "CUSTOM_OPENAI_URL": url,
    "CUSTOM_OPENAI_MODEL": model,
}
lines = []
seen = set()
try:
    with open(path, encoding="utf-8") as f:
        raw = f.read().splitlines()
except FileNotFoundError:
    raw = []
for line in raw:
    stripped = line.strip()
    if not stripped or stripped.startswith("#"):
        lines.append(line)
        continue
    name = stripped.split("=", 1)[0]
    name = name[7:].lstrip() if name.startswith("export ") else name
    if name in wanted:
        lines.append(f"{name}={wanted[name]}")
        seen.add(name)
    else:
        lines.append(line)
for name, val in wanted.items():
    if name not in seen:
        lines.append(f"{name}={val}")
with open(path, "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")
os.chmod(path, 0o600)
PY
}

ensure_bashrc_source() {
  local rc="$HOME/.bashrc"
  local marker="# homelab custom-openai provider"
  touch "$rc"
  if grep -Fq "$marker" "$rc" 2>/dev/null; then
    return 0
  fi
  cat >> "$rc" <<EOF

$marker
[ -f "$ENV_FILE" ] && set -a && . "$ENV_FILE" && set +a
EOF
}

backup_file() {
  local f="$1"
  [ -f "$f" ] || return 0
  cp -a "$f" "$f.bak"
}

discover_models() {
  local url="$1" json
  json="$(curl -fsS --max-time 8 \
    -H "Authorization: Bearer ${CUSTOM_OPENAI_API_KEY}" \
    -H "Content-Type: application/json" \
    "$url/models" 2>/dev/null || true)"
  [ -n "$json" ] || return 0
  /usr/bin/python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
items = data.get("data") or data.get("models") or []
ids = []
for it in items:
    if isinstance(it, str):
        ids.append(it)
    elif isinstance(it, dict):
        mid = it.get("id") or it.get("name")
        if mid:
            ids.append(str(mid))
for mid in ids[:30]:
    print(mid)
' <<<"$json"
}

# ── OpenCode ──────────────────────────────────────────────────────────────────
configure_opencode() {
  local cfg="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/opencode.json"
  mkdir -p "$(dirname "$cfg")"
  backup_file "$cfg"
  export OC_URL="$BASE_URL" OC_MODEL="$MODEL" OC_PROVIDER="$PROVIDER_ID" OC_NAME="$PROVIDER_NAME" OC_ENV_KEY="$ENV_KEY"
  /usr/bin/python3 - "$cfg" <<'PY'
import json, os, sys
path = sys.argv[1]
url = os.environ["OC_URL"]
model = os.environ["OC_MODEL"]
pid = os.environ["OC_PROVIDER"]
name = os.environ["OC_NAME"]
env_key = os.environ["OC_ENV_KEY"]
try:
    with open(path, encoding="utf-8") as f:
        cfg = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    cfg = {"$schema": "https://opencode.ai/config.json"}

v2 = {
    "name": name,
    "env": [env_key],
    "package": "@opencode-ai/llm/providers/openai-compatible",
    "settings": {
        "baseURL": url,
        "apiKey": "{env:%s}" % env_key,
    },
    "models": {
        model: {
            "name": model,
            "capabilities": {"tools": True, "input": ["text"], "output": ["text"]},
        }
    },
}
v1 = {
    "npm": "@ai-sdk/openai-compatible",
    "name": name,
    "options": {
        "baseURL": url,
        "apiKey": "{env:%s}" % env_key,
    },
    "models": {
        model: {
            "name": model,
            "capabilities": {"tools": True, "json": True, "vision": False, "reasoning": False},
        }
    },
}
cfg.setdefault("providers", {})[pid] = v2
cfg.setdefault("provider", {})[pid] = v1
with open(path, "w", encoding="utf-8") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
os.chmod(path, 0o600)
print(path)
PY
}

# ── Pi Agent ──────────────────────────────────────────────────────────────────
configure_pi() {
  local cfg="$HOME/.pi/agent/models.json"
  mkdir -p "$(dirname "$cfg")"
  backup_file "$cfg"
  export PI_URL="$BASE_URL" PI_MODEL="$MODEL" PI_PROVIDER="$PROVIDER_ID" PI_NAME="$PROVIDER_NAME" PI_ENV_KEY="$ENV_KEY"
  /usr/bin/python3 - "$cfg" <<'PY'
import json, os, sys
path = sys.argv[1]
url = os.environ["PI_URL"]
model = os.environ["PI_MODEL"]
pid = os.environ["PI_PROVIDER"]
name = os.environ["PI_NAME"]
env_key = os.environ["PI_ENV_KEY"]
try:
    with open(path, encoding="utf-8") as f:
        cfg = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    cfg = {"$schema": "https://pi.dev/schemas/models.schema.json", "providers": {}}
cfg.setdefault("providers", {})
cfg["providers"][pid] = {
    "name": name,
    "baseUrl": url,
    "api": "openai-completions",
    "apiKey": "$" + env_key,
    "models": [{
        "id": model,
        "name": model,
        "reasoning": False,
        "input": ["text"],
        "contextWindow": 128000,
        "maxTokens": 8192,
        "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0},
    }],
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
os.chmod(path, 0o600)
print(path)
PY
}

# ── Hermes ────────────────────────────────────────────────────────────────────
configure_hermes() {
  upsert_env_file "$HOME/.hermes/.env"
  if ! "$HERMES_BIN" config set "providers.${PROVIDER_ID}.api" "$BASE_URL" >/dev/null; then
    warn "hermes config set providers.${PROVIDER_ID}.api rifiutato — riprovo con --force"
    "$HERMES_BIN" config set --force "providers.${PROVIDER_ID}.api" "$BASE_URL" >/dev/null
  fi
  "$HERMES_BIN" config set --force "providers.${PROVIDER_ID}.key_env" "$ENV_KEY" >/dev/null || true
  "$HERMES_BIN" config set --force "providers.${PROVIDER_ID}.transport" "chat_completions" >/dev/null || true
  "$HERMES_BIN" config set --force "providers.${PROVIDER_ID}.default_model" "$MODEL" >/dev/null || true
  echo "$HOME/.hermes/config.yaml"
}

# ── Main ──────────────────────────────────────────────────────────────────────
command -v curl >/dev/null || error "curl non trovato"
command -v python3 >/dev/null || error "python3 non trovato"
[ -x /usr/bin/python3 ] || error "/usr/bin/python3 non trovato"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  PROVIDER CUSTOM OPENAI — OpenCode / Hermes / Pi"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

info "Verifica installazioni..."
FOUND=0
if [ -n "$OPENCODE_BIN" ]; then ok "OpenCode     ($OPENCODE_BIN)"; FOUND=1; else warn "OpenCode     non installato — skip"; fi
if [ -n "$HERMES_BIN" ]; then ok "Hermes Agent ($HERMES_BIN)"; FOUND=1; else warn "Hermes Agent non installato — skip"; fi
if [ -n "$PI_BIN" ]; then ok "Pi Agent     ($PI_BIN)"; FOUND=1; else warn "Pi Agent     non installato — skip"; fi
echo ""
[ "$FOUND" -eq 1 ] || error "Nessun agente installato. Esegui prima setup-bastion.sh"

[ -n "$OPENCODE_BIN$HERMES_BIN$PI_BIN" ] || error "Nessun agente compatibile con API OpenAI è installato."

echo ""
prompt CUSTOM_OPENAI_URL "URL API (es. https://api.example.com/v1): "
[ -n "${CUSTOM_OPENAI_URL:-}" ] || error "URL vuoto"
BASE_URL="$(normalize_url "$CUSTOM_OPENAI_URL")"
ok "URL normalizzato: $BASE_URL"

prompt CUSTOM_OPENAI_API_KEY "API key: " 1
[ -n "${CUSTOM_OPENAI_API_KEY:-}" ] || error "API key vuota"
export CUSTOM_OPENAI_API_KEY

MODEL="${CUSTOM_OPENAI_MODEL:-}"
if [ -z "$MODEL" ]; then
  info "Interrogo $BASE_URL/models ..."
  mapfile -t MODELS < <(discover_models "$BASE_URL")
  if [ "${#MODELS[@]}" -eq 1 ]; then
    MODEL="${MODELS[0]}"
    ok "Modello rilevato: $MODEL"
  elif [ "${#MODELS[@]}" -gt 1 ]; then
    echo ""
    echo "Modelli disponibili:"
    for i in "${!MODELS[@]}"; do
      printf "  %d) %s\n" $((i + 1)) "${MODELS[$i]}"
    done
    echo ""
    while true; do
      read -r -p "Scelta (1-${#MODELS[@]}) oppure nome modello: " SEL </dev/tty
      if echo "$SEL" | grep -qE '^[0-9]+$' && [ "$SEL" -ge 1 ] && [ "$SEL" -le "${#MODELS[@]}" ]; then
        MODEL="${MODELS[$((SEL - 1))]}"
        break
      elif [ -n "$SEL" ]; then
        MODEL="$SEL"
        break
      fi
    done
  else
    prompt MODEL "Nome modello (es. gpt-4o): "
  fi
fi
[ -n "$MODEL" ] || error "Modello vuoto"
ok "Modello: $MODEL"
echo ""

export CUSTOM_OPENAI_URL="$BASE_URL"
upsert_env_file "$ENV_FILE"
ensure_bashrc_source
set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a
ok "Credenziali salvate in $ENV_FILE (chmod 600)"
echo ""

APPLIED=0
if [ -n "$OPENCODE_BIN" ]; then
  info "Configuro OpenCode..."
  oc_path="$(configure_opencode)"
  ok "OpenCode: provider $PROVIDER_ID in $oc_path"
  APPLIED=1
fi
if [ -n "$HERMES_BIN" ]; then
  info "Configuro Hermes Agent..."
  h_path="$(configure_hermes)"
  ok "Hermes: providers.$PROVIDER_ID in $h_path"
  APPLIED=1
fi
if [ -n "$PI_BIN" ]; then
  info "Configuro Pi Agent..."
  pi_path="$(configure_pi)"
  ok "Pi: provider $PROVIDER_ID in $pi_path"
  APPLIED=1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ "$APPLIED" -eq 1 ]; then
  ok "Provider custom OpenAI applicato."
  echo ""
  echo "  ID provider : $PROVIDER_ID"
  echo "  URL         : $BASE_URL"
  echo "  Modello     : $MODEL"
  echo "  Env         : $ENV_KEY  (in $ENV_FILE)"
  echo ""
  echo "  OpenCode : /connect non serve; seleziona $PROVIDER_ID/$MODEL da /models"
  echo "  Hermes   : /model custom:$PROVIDER_ID:$MODEL"
  echo "  Pi       : /model  →  $PROVIDER_ID"
  echo ""
  echo "  Apri un nuovo shell (o: source $ENV_FILE) perché la API key sia nel PATH."
else
  warn "Nessuna configurazione scritta."
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
