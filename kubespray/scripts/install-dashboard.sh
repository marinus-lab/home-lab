#!/usr/bin/env bash
# Installa Kubernetes Dashboard (manifest ufficiale v2.7.0) nel cluster.
set -euo pipefail

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${BLUE}[dash]${NC} $*"; }
ok()   { echo -e "${GREEN}[dash]${NC} ✅ $*"; }

NAMESPACE="kubernetes-dashboard"

info "Applicazione manifest ufficiale Kubernetes Dashboard (v2.7.0)..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml

info "Creazione ServiceAccount admin-dashboard..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-dashboard
  namespace: $NAMESPACE
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
    namespace: $NAMESPACE
EOF

ok "Dashboard installata e ServiceAccount admin-dashboard configurato."
echo ""
info "Per generare un nuovo token di accesso (validità 12h):"
echo "  kubectl -n $NAMESPACE create token admin-dashboard --duration=12h"
echo ""
info "Per accedere via port-forward:"
echo "  kubectl -n $NAMESPACE port-forward svc/kubernetes-dashboard 8443:443"
echo "  poi apri: https://localhost:8443"
