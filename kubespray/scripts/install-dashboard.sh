#!/usr/bin/env bash
# Installa Kubernetes Dashboard nel cluster (Kubespray ha rimosso l'addon
# dashboard upstream dalla v2.21+, quindi dashboard_enabled è una var morta).
#
# Uso: ./install-dashboard.sh          # installa dashboard + admin user + stampa token
#
# Requisiti: kubectl configurato (KUBECONFIG o ~/.kube/config), helm (opzionale)
set -euo pipefail

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${BLUE}[dash]${NC} $*"; }
ok()   { echo -e "${GREEN}[dash]${NC} ✅ $*"; }
warn() { echo -e "${YELLOW}[dash]${NC} ⚠️  $*"; }

RELEASE_NAME="kubernetes-dashboard"
NAMESPACE="kubernetes-dashboard"

# ── 1. Installa via helm (metodo ufficiale raccomandato) ─────────────────────
if ! helm repo list 2>/dev/null | grep -q "^kubernetes-dashboard"; then
  info "Aggiungo repo helm kubernetes-dashboard..."
  helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
fi
helm repo update >/dev/null

info "Installo/aggiorno $RELEASE_NAME via helm..."
helm upgrade --install "$RELEASE_NAME" kubernetes-dashboard/kubernetes-dashboard \
  --create-namespace \
  --namespace "$NAMESPACE" \
  --set app.ingress.enabled=false \
  --set app.metricsScraper.enabled=true \
  --wait --timeout 5m

ok "Dashboard installata nel namespace $NAMESPACE"

# ── 2. Crea ServiceAccount admin + ClusterRoleBinding (idempotente) ──────────
info "Creo ServiceAccount admin-dashboard..."
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-dashboard
  namespace: kubernetes-dashboard
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-dashboard
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: admin-dashboard
    namespace: kubernetes-dashboard
EOF
ok "ServiceAccount admin-dashboard creato (cluster-admin)"

# ── 3. Genera token di accesso ───────────────────────────────────────────────
info "Genero token di accesso (validità 12h)..."
TOKEN=$(kubectl -n "$NAMESPACE" create token admin-dashboard --duration=12h 2>/dev/null || true)

# ── 4. Avvia proxy e stampa info accesso ─────────────────────────────────────
echo ""
ok "════════════════════════════════════════════════════════"
ok " Kubernetes Dashboard installato"
ok "════════════════════════════════════════════════════════"
echo ""
info "Per accedere, esegui in un altro terminale:"
echo ""
echo "  kubectl -n $NAMESPACE port-forward svc/$RELEASE_NAME-kong-proxy 8443:443"
echo ""
echo "  poi apri:  https://localhost:8443"
echo ""
if [ -n "${TOKEN:-}" ]; then
  info "Token di accesso (12h):"
  echo ""
  echo "$TOKEN"
  echo ""
  info "Token salvato anche in /tmp/dashboard-token.txt"
  echo "$TOKEN" > /tmp/dashboard-token.txt
  chmod 600 /tmp/dashboard-token.txt
else
  warn "Token non generato ora (probabile default NS disallineato). Genera con:"
  echo "  kubectl -n $NAMESPACE create token admin-dashboard --duration=12h"
fi
echo ""
warn "NOTA: svc kong-proxy può chiamarsi diversamente. Verifica con:"
echo "  kubectl -n $NAMESPACE get svc"
