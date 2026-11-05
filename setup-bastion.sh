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
    "Node.js 26 Installation"
    "OpenCode AI Agent v2"
    "Hermes Agent"
    "Pi Agent"
    "Ansible & Proxmox"
    "Terraform & Packer"
    "kubectl"
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
        [ -f "$STATUS_FILE" ] && sed -i "s|^$idx:done:$name:$|$idx:done:$name_sed:$version|" "$STATUS_FILE" || true
        echo "  ✅ $name — $version"
    else
        echo "  ✅ $name — done"
    fi
}

# ─── List phases ─────────────────────────────────────────────────
list_phases() {
    echo "Fasi disponibili (usa --phase=N per eseguirle singolarmente):"
    echo "┌─────┬─────────────────────────────────────────────┐"
    printf "│ %-3s │ %-43s │\n" "ID" "Nome fase"
    echo "├─────┼─────────────────────────────────────────────┤"
    for i in "${!PHASE_NAMES[@]}"; do
        printf "│ %-3d │ %-43s │\n" "$i" "${PHASE_NAMES[$i]}"
    done
    echo "└─────┴─────────────────────────────────────────────┘"
}

# ─── Phase 1: Java 17 ────────────────────────────────────────────
_phase_0_java() {
    phase_start 0
    sudo apt-get update || { echo "⚠ apt update failed."; phase_end 0 "no repo"; exit 1; }
    if ! dpkg -s openjdk-17-jre-headless &>/dev/null; then
        sudo apt-get install -y openjdk-17-jre-headless || {
            echo "⚠ openjdk-17-jre-headless not found in repositories." >&2
            java -version 2>&1 | head -1 && {
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
}

# ─── Phase 2: System dependencies ─────────────────────────────────
_phase_1_deps() {
    phase_start 1
    sudo apt-get install -y curl gnupg software-properties-common git unzip \
        python3-pip python3-venv python3-pygments build-essential \
        tmux jq dnsutils netcat-openbsd htop aria2
    TMUX_VER="$(tmux -V 2>&1 | awk '{print $2}')"
    phase_end 1 "$TMUX_VER"
}

# ─── Phase 3: Vim Configuration ───────────────────────────────────
_phase_2_vim() {
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
}

# ─── Phase 4: Node.js 26 ─────────────────────────────────────────
_phase_3_nodejs() {
    phase_start 3
    curl -fsSL https://deb.nodesource.com/setup_26.x | sudo -E bash -
    sudo apt-get install -y nodejs
    NODE_VER="$(node --version 2>&1 | cut -c2-)"
    phase_end 3 "$NODE_VER"
}

# ─── Phase 5: OpenCode AI Agent ───────────────────────────────────
_phase_4_opencode() {
    phase_start 4
    curl -fsSL https://opencode.ai/v2/install | bash
    export PATH="$HOME/.opencode/bin:$PATH"
    OPENCODE_VER="$(opencode --version 2>&1 | head -1 | awk '{print $NF}')"
    phase_end 4 "$OPENCODE_VER"
}

# ─── Phase 6: Hermes Agent ────────────────────────────────────────
_phase_5_hermes() {
    phase_start 5
    curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- --non-interactive
    export PATH="$HOME/.local/bin:$PATH"
    HERMES_VER="$(hermes --version 2>&1 | head -1 | awk '{print $NF}')"
    phase_end 5 "$HERMES_VER"
}

# ─── Phase 7: Pi Agent ──────────────────────────────────────────
_phase_6_pi() {
    phase_start 6
    curl -fsSL https://pi.dev/install.sh | setsid -w sh
    export PATH="$HOME/.local/bin:$HOME/.pi/agent/bin:$PATH"
    PI_VER="$(pi --version 2>&1 | head -1 | awk '{print $NF}')"
    phase_end 6 "$PI_VER"
}

# ─── Phase 8: Ansible & Proxmox ───────────────────────────────────
_phase_7_ansible() {
    phase_start 7
    sudo add-apt-repository -y ppa:ansible/ansible
    sudo apt-get update
    sudo apt-get install -y ansible
    sudo pip3 install --break-system-packages proxmoxer requests
    ansible-galaxy collection install community.proxmox
    ANSIBLE_VER="$(ansible --version 2>&1 | head -1 | sed 's/.*\[core \([^]]*\).*/\1/')"
    phase_end 7 "$ANSIBLE_VER"
}

# ─── Phase 9: Terraform & Packer ──────────────────────────────────
_phase_8_terraform() {
    phase_start 8
    curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --batch --yes --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
    sudo apt-get update
    sudo apt-get install -y terraform packer
    TF_VER="$(terraform --version 2>&1 | head -1 | awk '{print $2}')"
    PACKER_VER="$(packer --version 2>&1)"
    phase_end 8 "TF $TF_VER / Packer $PACKER_VER"
}

# ─── Phase 10: kubectl ────────────────────────────────────────────
_phase_9_kubectl() {
    phase_start 9
    curl -fsSL "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" -o /tmp/kubectl
    sudo install -o root -g root -m 0755 /tmp/kubectl /usr/local/bin/kubectl
    rm -f /tmp/kubectl
    KUBECTL_VER="$(kubectl version --client -o yaml 2>/dev/null | grep -m1 gitVersion | awk '{print $2}')"
    phase_end 9 "$KUBECTL_VER"
}

# ─── Phase 11: Kubespray venv ─────────────────────────────────────
_phase_10_kubespray() {
    phase_start 10
    
    # Controllo: se venv esiste già, salti
    if [ -d "$HOME/kubespray-env" ] && [ -f "$HOME/kubespray-env/bin/pip" ]; then
        echo "ℹ️  Kubespray venv già esistente — salto la creazione"
        phase_end 10
        return 0
    fi
    
    mkdir -p "$HOME/kubespray-env"
    python3 -m venv "$HOME/kubespray-env"
    
    # Usa il python del venv in modo sicuro
    "$HOME/kubespray-env/bin/pip" install --upgrade pip
    echo "📥 Installing Kubespray Python dependencies..."
    
    TMP_DIR=$(mktemp -d)
    
    # Messaggio progressivo durante il clone
    echo "   ↳ Clonazione Kubespray da GitHub (potrebbe richiedere 1-2 minuti)..."
    if git clone --depth 1 --branch v2.32.0 https://github.com/kubernetes-sigs/kubespray.git "$TMP_DIR/kubespray"; then
        echo "   ✅ Git clone completato"
    else
        echo "   ⚠ Git clone fallito, riprovo con profondità 0..."
        rm -rf "$TMP_DIR"
        TMP_DIR=$(mktemp -d)
        git clone --branch v2.32.0 https://github.com/kubernetes-sigs/kubespray.git "$TMP_DIR/kubespray"
    fi
    
    if [ -f "$TMP_DIR/kubespray/requirements.txt" ]; then
        "$HOME/kubespray-env/bin/pip" install -r "$TMP_DIR/kubespray/requirements.txt"
        echo "✅ Kubespray dependencies installed in venv!"
    else
        "$HOME/kubespray-env/bin/pip" install ansible-core cryptography netaddr jinja2
    fi
    
    rm -rf "$TMP_DIR"
    
    phase_end 10
}

# ─── Phase 12: SSH Key ──────────────────────────────────────────
_phase_11_ssh() {
    phase_start 11
    if [ ! -f "$HOME/.ssh/id_rsa" ]; then
        ssh-keygen -t rsa -b 4096 -f "$HOME/.ssh/id_rsa" -N ""
        echo "✅ New SSH key generated."
    else
        echo "i️  SSH key already exists, skipping."
    fi
    phase_end 11
}

# ─── Phase 13: less/Pygmentize ───────────────────────────────────
_phase_12_less() {
    phase_start 12
    cat > "$HOME/.lessfilter" << 'LESSFILTER'
#!/bin/bash
case "$1" in
    *Makefile*|*makefile*|*\.mk|\\.
    *.awk|*.c|*.h|*.sh|*.bash|*.zsh|*.py|*.rb|\\.
    *.js|*.mjs|*.cjs|*.jsx|*.ts|*.tsx|*.go|*.rs|\\.
    *.java|*.kt|*.scala|\\.
    *.yaml|*.yml|*.json|*.xml|*.toml|*.ini|*.cfg|*.conf|\\.
    *.md|*.rst|*.txt|\\.
    *.sql|*.html|*.css|*.scss|*.less|*.php|*.pl|*.lua|\\.
    *.vim|*.tf|*.hcl|*.tfvars|*.tfstate|\\.
    *.dockerfile|*.Dockerfile|*.env|*.envrc|\\.
    *.patch|*.diff|\\.
    *.groovy|*.gradle|\\.
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
    phase_end 12
}

# ─── Error handling ────────────────────────────────────────────────
BOLD='\033[1m'
YELLOW='\033[1;33m'
NC='\033[0m'

cleanup() {
    # Se SKIP_CLEANUP è true, non fare nulla
    if [ "${SKIP_CLEANUP:-false}" = "true" ]; then
        return 0
    fi

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

# ─── Argomenti da riga di comando ─────────────────────────────────
SHOW_LIST=false
SINGLE_PHASE=""

# Flag per evitare cleanup in modalità --list/--help (inizializzato a true)
SKIP_CLEANUP=true

# Flag per modalità non-tmux (usato quando si specifica --phase o --all)
FORCE_NO_TMUX=false

while [ $# -gt 0 ]; do
    case "$1" in
        --list)
            SHOW_LIST=true
            shift
            ;;
        --phase=*)
            SINGLE_PHASE="${1#*=}"
            FORCE_NO_TMUX=true
            shift
            ;;
        --all)
            FORCE_NO_TMUX=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --list              Mostra le fasi disponibili"
            echo "  --phase=N           Esegui solo la fase N (es. --phase=3)"
            echo "  --phase=N,M         Esegui le fasi N e M (es. --phase=0,9)"
            echo "  --phase=N-M         Esegui le fasi da N a M inclusive (es. --phase=8-10)"
            echo "  --all               Esegui tutte le fasi (default)"
            echo "  --help, -h          Mostra questo messaggio"
            exit 0
            ;;
        *)
            echo "Argomento sconosciuto: $1" >&2
            exit 1
            ;;
    esac
done

# ─── Tmux launcher ───────────────────────────────────────────────
SCRIPT_PATH="$(readlink -f "$0")"

if $SHOW_LIST; then
    list_phases
    exit 0
fi

# Funzione per eseguire una fase singola senza tmux
_run_single_phase() {
    local phase=$1
    init_status_file
    create_dashboard_script

    # Modalità tmux o classica?
    # Usa tmux SOLO se non è forzata la modalità non-tmux e non siamo già in tmux
    if [ -z "${TMUX:-}" ] && [ -z "${BASTION_NO_TMUX:-}" ] && [ "${FORCE_NO_TMUX:-false}" = "false" ]; then
        echo "🚀 Launching setup in tmux dashboard mode..."

        if ! command -v tmux &>/dev/null; then
            sudo apt-get update -qq 2>/dev/null
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq tmux >/dev/null 2>&1 || {
                echo "⚠ tmux unavailable, falling back to classic mode."
                exec bash "$SCRIPT_PATH" --phase="$phase"
            }
        fi

        tmux kill-session -t bastion-setup 2>/dev/null || true
        tmux new-session -d -s bastion-setup 2>/dev/null || {
            echo "⚠ Could not create tmux session, falling back." >&2
            exec bash "$SCRIPT_PATH" --phase="$phase"
        }
        tmux split-window -v -l 15 -b -t bastion-setup 2>/dev/null || true
        tmux send-keys -t bastion-setup.0 "exec bash $DASHBOARD_SCRIPT $STATUS_FILE" Enter 2>/dev/null || true
        tmux send-keys -t bastion-setup.1 "export LOG_FILE='$LOG_FILE'" Enter "BASTION_NO_TMUX=1 script -q -c 'bash $SCRIPT_PATH --phase=$phase' \"\$LOG_FILE\"" Enter 2>/dev/null || true
        tmux attach-session -t bastion-setup
        exit 0
    fi

    # Modalità classica (senza tmux)
    if [ "${FORCE_NO_TMUX:-false}" = "true" ] || [ -n "${BASTION_NO_TMUX:-}" ]; then
        echo "Classic mode (no tmux dashboard)."
    fi

    # Esegui la fase specificata
    case "$phase" in
        0) _phase_0_java ;;
        1) _phase_1_deps ;;
        2) _phase_2_vim ;;
        3) _phase_3_nodejs ;;
        4) _phase_4_opencode ;;
        5) _phase_5_hermes ;;
        6) _phase_6_pi ;;
        7) _phase_7_ansible ;;
        8) _phase_8_terraform ;;
        9) _phase_9_kubectl ;;
        10) _phase_10_kubespray ;;
        11) _phase_11_ssh ;;
        12) _phase_12_less ;;
        *)
            echo "Fase non valida: $phase (valori consentiti: 0-12)" >&2
            exit 1
            ;;
    esac
}

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

# ─── Parse phase ranges/comma-separated ────────────────────────────
parse_phases() {
    local input="$1"
    local result=""

    # Split by comma
    IFS=',' read -ra PARTS <<< "$input"
    for part in "${PARTS[@]}"; do
        if [[ "$part" == *-* ]]; then
            # Range N-M
            local start end
            start="${part%-*}"
            end="${part#*-}"
            for ((i=start; i<=end; i++)); do
                result="$result $i"
            done
        else
            result="$result $part"
        fi
    done

    echo $result | tr ' ' '\n' | sort -nu
}

# ─── OS check ─────────────────────────────────────────────────
if ! grep -qiE 'debian|ubuntu' /etc/os-release 2>/dev/null; then
    echo "❌ This script supports Debian/Ubuntu only." >&2
    exit 1
fi

# ─── Esecuzione ────────────────────────────────────────────────────
echo "================================================================="
echo "🏗️  Bastion Init: OpenCode-AI, Java 17, IaC & Kubernetes"
echo "================================================================="

if [ -n "$SINGLE_PHASE" ]; then
    # Parse phase list/range
    PHASES_TO_RUN=$(parse_phases "$SINGLE_PHASE")

    for phase in $PHASES_TO_RUN; do
        _run_single_phase "$phase"
    done
else
    # Esecuzione completa (default)
    _phase_0_java
    _phase_1_deps
    _phase_2_vim
    _phase_3_nodejs
    _phase_4_opencode
    _phase_5_hermes
    _phase_6_pi
    _phase_7_ansible
    _phase_8_terraform
    _phase_9_kubectl
    _phase_10_kubespray
    _phase_11_ssh
    _phase_12_less
fi

echo ""
echo "================================================================="
echo "🎉 BASTION SETUP COMPLETED SUCCESSFULLY!"
echo "================================================================="
echo "• OpenJDK 17 Headless installed."
echo "• Vim (desert theme, line numbers)."
echo "• Node.js 26 + OpenCode v2 + Hermes Agent + Pi Agent."
echo "• Ansible + Proxmox integration."
echo "• Terraform + Packer installed."
echo "• Kubespray venv ready at $HOME/kubespray-env"
echo "• less + pygmentize (rrt theme) for syntax-highlighted file viewing."
echo "================================================================="
echo ""
echo ""
echo "📄 Full log: $LOG_FILE"