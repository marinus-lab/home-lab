#!/bin/bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════════
# Bastion Init: OpenCode-AI, Java 17, IaC & Kubernetes
# ═══════════════════════════════════════════════════════════════════

STATUS_FILE="/tmp/bastion-setup.status"
DASHBOARD_SCRIPT="/tmp/bastion-dashboard.sh"
LOG_FILE="${LOG_FILE:-/tmp/bastion-setup-$(date +%Y%m%d-%H%M%S).log}"

# ─── Phase definitions ───────────────────────────────────────────
PHASE_NAMES=(
    "Java 17 Installation"
    "System Update & Dependencies"
    "Vim Configuration"
    "Node.js 22 Installation"
    "OpenCode AI Agent"
    "OpenClaude"
    "Ansible & Proxmox"
    "Terraform & Packer"
    "Kubespray Python Environment"
    "SSH Key Generation"
    "less + Pygmentize Configuration"
)

# ─── Status helpers ──────────────────────────────────────────────
init_status_file() {
    : > "$STATUS_FILE"
    for i in "${!PHASE_NAMES[@]}"; do
        echo "$i:pending:${PHASE_NAMES[$i]}:" >> "$STATUS_FILE"
    done
}

set_phase_status() {
    local idx=$1 status=$2
    [ -f "$STATUS_FILE" ] && sed -i "s/^$idx:[^:]*:/$idx:$status:/" "$STATUS_FILE" || true
}

CURRENT_PHASE=""
phase_start() {
    CURRENT_PHASE=$1
    set_phase_status "$1" "running"
    echo ""
    echo "  ─────────────────────────────────────────────"
    echo "  ▶ ${PHASE_NAMES[$1]}"
    echo "  ─────────────────────────────────────────────"
}

phase_end() {
    local idx=$1 version="${2:-}"
    local name="${PHASE_NAMES[$idx]}"
    # Escape & for sed replacement (it's a metachar in sed's replacement string)
    local name_sed="${name//&/\\&}"
    set_phase_status "$idx" "done"
    if [ -n "$version" ]; then
        [ -f "$STATUS_FILE" ] && sed -i "s/^$idx:done:$name:$/$idx:done:$name_sed:$version/" "$STATUS_FILE" || true
        echo "  ✅ $name — $version"
    else
        echo "  ✅ $name — done"
    fi
}

# ─── Error handling ────────────────────────────────────────────
BOLD='\033[1m'
YELLOW='\033[1;33m'
NC='\033[0m'

cleanup() {
    local ec=$?
    if [ -n "$CURRENT_PHASE" ] && [ -f "$STATUS_FILE" ]; then
        if [ $ec -ne 0 ]; then
            set_phase_status "$CURRENT_PHASE" "fail"
        fi
    fi
    # Always show the "Press ENTER" prompt, then clean up
    tmux select-pane -t bastion-setup.1 2>/dev/null || true
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if [ $ec -eq 0 ]; then
        printf "${BOLD}${YELLOW}              ✅ ALL DONE — Press ENTER to close this session.${NC}\n"
    else
        printf "${BOLD}${YELLOW}           ❌ PHASE FAILED — Press ENTER to close this session.${NC}\n"
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    read -r || true
    rm -f /tmp/bastion-setup.status /tmp/bastion-dashboard.sh 2>/dev/null || true
    tmux kill-session -t bastion-setup 2>/dev/null || true
}
trap cleanup EXIT

# ─── Dashboard script generation ────────────────────────────────
create_dashboard_script() {
    cat > "$DASHBOARD_SCRIPT" << 'DASHBOARD'
#!/bin/bash
STATUS_FILE="${1:-/tmp/bastion-setup.status}"

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
GRAY='\033[0;90m'
CYAN='\033[0;36m'
NC='\033[0m'

draw() {
    clear
    printf "${BOLD}${CYAN}  ╔══════════════════════════════════════════════════╗${NC}\n"
    printf "${BOLD}${CYAN}  ║         BASTION SETUP — INSTALLATION DASHBOARD   ║${NC}\n"
    printf "${BOLD}${CYAN}  ╚══════════════════════════════════════════════════╝${NC}\n"
    printf "\n"
    while IFS=: read -r idx status name version; do
        idx=$((10#$idx))
        case "$status" in
            pending) sym="${GRAY}⏳${NC}" ;;
            running) sym="${YELLOW}▶${NC}" ;;
            done)    sym="${GREEN}✅${NC}" ;;
            fail)    sym="${RED}❌${NC}" ;;
            *)       sym="${GRAY}?${NC}" ;;
        esac
        if [ -n "$version" ]; then
            printf "  %b  %s (%s)\n" "$sym" "$name" "$version"
        else
            printf "  %b  %s\n" "$sym" "$name"
        fi
    done < "$STATUS_FILE"
    printf "\n"
    printf "${GRAY}  Waiting for phases to complete...${NC}\n"
}

while true; do
    sleep 1
    draw
    has_fail=false
    all_done=true
    while IFS=: read -r idx status name version; do
        [ "$status" = "running" ] && continue 2
        [ "$status" = "fail" ] && has_fail=true
        [ "$status" != "done" ] && all_done=false
    done < "$STATUS_FILE"
    if $has_fail; then
        draw
        printf "\n${BOLD}${RED}  ❌ A PHASE FAILED — check the installation pane below.${NC}\n"
        while [ -f "$STATUS_FILE" ]; do sleep 1; done
        exit 1
    fi
    if $all_done; then
        draw
        printf "\n${BOLD}${GREEN}  🎉 ALL PHASES COMPLETED SUCCESSFULLY!${NC}\n"
        while [ -f "$STATUS_FILE" ]; do sleep 1; done
        exit 0
    fi
done
DASHBOARD
    chmod +x "$DASHBOARD_SCRIPT"
}

# ─── Tmux launcher ───────────────────────────────────────────────
SCRIPT_PATH="$(readlink -f "$0")"

if [ -z "${TMUX:-}" ] && [ -z "${BASTION_NO_TMUX:-}" ]; then
    echo "🚀 Launching setup in tmux dashboard mode..."

    if ! command -v tmux &>/dev/null; then
        sudo apt-get update -qq 2>/dev/null
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq tmux >/dev/null 2>&1 || {
            echo "⚠ tmux unavailable, falling back to classic mode."
            exec bash "$SCRIPT_PATH" --no-tmux
        }
    fi

    init_status_file
    create_dashboard_script

    tmux kill-session -t bastion-setup 2>/dev/null || true
    tmux new-session -d -s bastion-setup 2>/dev/null || {
        echo "⚠ Could not create tmux session, falling back." >&2
        exec bash "$SCRIPT_PATH" --no-tmux
    }
    tmux split-window -v -l 15 -b -t bastion-setup 2>/dev/null || true
    tmux send-keys -t bastion-setup.0 "exec bash $DASHBOARD_SCRIPT $STATUS_FILE" Enter 2>/dev/null || true
    tmux send-keys -t bastion-setup.1 "export LOG_FILE='$LOG_FILE'" Enter "BASTION_NO_TMUX=1 script -q -c 'bash $SCRIPT_PATH' \"\$LOG_FILE\"" Enter 2>/dev/null || true
    tmux attach-session -t bastion-setup
    exit 0
fi

if [ "${1:-}" = "--no-tmux" ]; then
    echo "Classic mode (no tmux dashboard)."
fi

# ─── OS check ─────────────────────────────────────────────────
if ! grep -qiE 'debian|ubuntu' /etc/os-release 2>/dev/null; then
    echo "❌ This script supports Debian/Ubuntu only." >&2
    exit 1
fi

echo "================================================================="
echo "🏗️  Bastion Init: OpenCode-AI, Java 17, IaC & Kubernetes"
echo "================================================================="

# 1. Java 17 (standalone per visibilità in dashboard)
phase_start 0
sudo apt-get update || { echo "⚠ apt update failed."; phase_end 0 "no repo"; exit 1; }
if ! dpkg -s openjdk-17-jre-headless &>/dev/null; then
    sudo apt-get install -y openjdk-17-jre-headless || {
        echo "⚠ openjdk-17-jre-headless not found in repositories." >&2
        java -version 2>&1 | head -1 && {
            # Java is already available via different package
            echo "ℹ️  Java binary found, proceeding."
        } || {
            phase_end 0 "pkg missing"
            exit 1
        }
    }
else
    echo "ℹ️  openjdk-17-jre-headless already installed."
fi
JAVA_VER="$(java -version 2>&1 | head -n 1 | cut -d'"' -f2)"
phase_end 0 "$JAVA_VER"

# 2. System update and base dependencies
phase_start 1
sudo apt-get install -y curl gnupg software-properties-common git unzip \
    python3-pip python3-venv python3-pygments build-essential \
    tmux jq dnsutils netcat-openbsd htop aria2
TMUX_VER="$(tmux -V 2>&1 | awk '{print $2}')"
phase_end 1 "$TMUX_VER"

# 3. Vim configuration (Desert theme + line numbers)
phase_start 2
sudo apt-get install -y vim
cat > "$HOME/.vimrc" << 'EOF'
set number
colorscheme desert
EOF
mkdir -p "$HOME/.vim/pack/plugins/start"
if [ ! -d "$HOME/.vim/pack/plugins/start/vim-terraform" ]; then
    git clone https://github.com/hashivim/vim-terraform.git "$HOME/.vim/pack/plugins/start/vim-terraform"
fi
VIM_VER="$(vim --version 2>&1 | head -1 | awk '{print $5}')"
phase_end 2 "$VIM_VER"

# 4. Node.js 22 installation
phase_start 3
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt-get install -y nodejs
NODE_VER="$(node --version 2>&1 | cut -c2-)"
phase_end 3 "$NODE_VER"

# 5. OpenCode AI Agent
# 5. OpenCode AI Agent
phase_start 4
sudo npm i -g opencode-ai
echo "🧠 Configuring OpenCode Working Memory plugin..."
mkdir -p "$HOME/.opencode"
cat > "$HOME/.opencode/opencode.json" << 'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "plugin": ["opencode-working-memory"]
}
EOF
cat > "$HOME/.opencode/tui.json" << 'EOF'
{
  "$schema": "https://opencode.ai/tui.json",
  "plugin": ["opencode-working-memory"]
}
EOF
OPENCODE_VER="$(opencode --version 2>&1 || npm list -g opencode-ai --depth=0 2>/dev/null | awk -F'@' '/opencode-ai/{print $2}')"
phase_end 4 "$OPENCODE_VER"

# 6. OpenClaude
phase_start 5
sudo npm i -g @gitlawb/openclaude
OPENCLAUDE_VER="$(npm list -g @gitlawb/openclaude --depth=0 2>/dev/null | awk -F'@' '/openclaude/{print $2}')"
phase_end 5 "$OPENCLAUDE_VER"

# 7. Ansible & Proxmox Integration
phase_start 6
sudo add-apt-repository -y ppa:ansible/ansible
sudo apt-get update
sudo apt-get install -y ansible
sudo pip3 install --break-system-packages proxmoxer requests
ansible-galaxy collection install community.proxmox
ANSIBLE_VER="$(ansible --version 2>&1 | head -1 | sed 's/.*\[core \([^]]*\).*/\1/')"
phase_end 6 "$ANSIBLE_VER"

# 8. HashiCorp Packer and Terraform
phase_start 7
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --batch --yes --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update
sudo apt-get install -y terraform packer
TF_VER="$(terraform --version 2>&1 | head -1 | awk '{print $2}')"
PACKER_VER="$(packer --version 2>&1)"
phase_end 7 "TF $TF_VER / Packer $PACKER_VER"

# 9. Python venv for Kubespray
phase_start 8
mkdir -p "$HOME/kubespray-env"
python3 -m venv "$HOME/kubespray-env"
source "$HOME/kubespray-env/bin/activate"
pip install --upgrade pip
echo "📥 Installing Kubespray Python dependencies..."
TMP_DIR=$(mktemp -d)
git clone --depth 1 https://github.com/kubernetes-sigs/kubespray.git "$TMP_DIR/kubespray"
if [ -f "$TMP_DIR/kubespray/requirements.txt" ]; then
    pip install -r "$TMP_DIR/kubespray/requirements.txt"
    echo "✅ Kubespray dependencies installed in venv!"
else
    pip install ansible-core cryptography netaddr jinja2
fi
rm -rf "$TMP_DIR"
deactivate
phase_end 8

# 10. SSH key generation
phase_start 9
if [ ! -f "$HOME/.ssh/id_rsa" ]; then
    ssh-keygen -t rsa -b 4096 -f "$HOME/.ssh/id_rsa" -N ""
    echo "✅ New SSH key generated."
else
    echo "ℹ️  SSH key already exists, skipping."
fi
phase_end 9

# 11. less + Pygmentize configuration (rrt theme)
phase_start 10
cat > "$HOME/.lessfilter" << 'LESSFILTER'
#!/bin/bash
case "$1" in
    *Makefile*|*makefile*|*\.mk|\
    *.awk|*.c|*.h|*.sh|*.bash|*.zsh|*.py|*.rb|\
    *.js|*.mjs|*.cjs|*.jsx|*.ts|*.tsx|*.go|*.rs|\
    *.java|*.kt|*.scala|\
    *.yaml|*.yml|*.json|*.xml|*.toml|*.ini|*.cfg|*.conf|\
    *.md|*.rst|*.txt|\
    *.sql|*.html|*.css|*.scss|*.less|*.php|*.pl|*.lua|\
    *.vim|*.tf|*.hcl|*.tfvars|*.tfstate|\
    *.dockerfile|*.Dockerfile|*.env|*.envrc|\
    *.patch|*.diff|\
    *.groovy|*.gradle|\
    *.zig|*.nim|*.tex|*.bib)
        pygmentize -O style=rrt -f terminal256 "$1" 2>/dev/null || cat "$1"
        ;;
    *)
        cat "$1"
        ;;
esac
LESSFILTER
chmod +x "$HOME/.lessfilter"
SHELL_RC="$HOME/.bashrc"
if ! grep -q 'lessfilter' "$SHELL_RC" 2>/dev/null; then
    cat >> "$SHELL_RC" << 'BASHRC'
# less + Pygmentize (rrt theme)
export LESSOPEN='|~/.lessfilter %s'
export LESS='-R'
BASHRC
fi
export LESSOPEN='|~/.lessfilter %s'
export LESS='-R'
echo "✅ less will use pygmentize (rrt) for syntax-highlighted file viewing."
phase_end 10

echo ""
echo "================================================================="
echo "🎉 BASTION SETUP COMPLETED SUCCESSFULLY!"
echo "================================================================="
echo "• OpenJDK 17 Headless installed."
echo "• Vim (desert theme, line numbers)."
echo "• Node.js 22 + OpenCode-AI + OpenClaude + Working Memory plugin."
echo "• Ansible + Proxmox integration."
echo "• Terraform + Packer installed."
echo "• Kubespray venv ready at $HOME/kubespray-env"
echo "• less + pygmentize (rrt theme) for syntax-highlighted file viewing."
echo "================================================================="
echo ""
echo ""
echo "📄 Full log: $LOG_FILE"
echo ""
