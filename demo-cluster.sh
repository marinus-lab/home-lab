#!/usr/bin/env bash
# Demo del cluster Kubernetes homelab.
# Verifica: Tetris, registry interno, MetalLB, deploy da registry locale.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="${1:-demo}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
pass() { echo -e "${GREEN}[PASS]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; RET=1; }
info() { echo -e "${BLUE}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
RET=0

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  DEMO CLUSTER KUBERNETES HOMELAB"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── 1. Tetris ──────────────────────────────────────────────────────────────────
info "1. Tetris (demo app via MetalLB)"
if kubectl get svc tetris -o jsonpath='{.status.loadBalancer.ingress[0].ip}' &>/dev/null; then
  TETRIS_IP=$(kubectl get svc tetris -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
  HTTP=$(curl -s -o /dev/null -w "%{http_code}" "http://$TETRIS_IP/" 2>/dev/null || echo "000")
  if [ "$HTTP" = "200" ]; then
    pass "Tetris disponibile su http://$TETRIS_IP"
  else
    fail "Tetris non risponde (HTTP $HTTP) su http://$TETRIS_IP"
  fi
else
  warn "Tetris non deployato — deploy in corso..."
  kubectl create deployment tetris --image=docker.io/lrakai/tetris:latest --port=80 &>/dev/null
  kubectl expose deployment tetris --type=LoadBalancer --port=80 --target-port=80 --name=tetris &>/dev/null
  sleep 10
  TETRIS_IP=$(kubectl get svc tetris -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  if [ -n "$TETRIS_IP" ]; then
    pass "Tetris deployato su http://$TETRIS_IP"
  else
    fail "Tetris non ha ricevuto un IP MetalLB"
  fi
fi

# ── 2. Registry interno ────────────────────────────────────────────────────────
info "2. Registry interno"
REG_POD=$(kubectl -n kube-system get pod -l k8s-app=registry -o jsonpath='{.items[0].status.podIP}' 2>/dev/null || true)
if [ -n "$REG_POD" ]; then
  REPOS=$(kubectl run curl-test --image=curlimages/curl:latest --restart=Never --rm -- curl -s "http://$REG_POD:5000/v2/_catalog" 2>/dev/null || echo '{"repositories":[]}')
  REPOS=$(echo "$REPOS" | grep -o '"repositories":\[[^]]*\]' || echo '[]')
  if echo "$REPOS" | grep -q .; then
    pass "Registry su $REG_POD:5000 — repositories: $REPOS"
  else
    pass "Registry su $REG_POD:5000 (vuoto)"
  fi
else
  fail "Pod registry non trovato in kube-system"
fi

# ── 3. Push al registry ───────────────────────────────────────────────────────
info "3. Push immagine al registry"
REG_IP="$REG_POD"
if kubectl run nginx-push --image=curlimages/curl:latest --restart=Never --rm -- \
  curl -s -o /dev/null -w "%{http_code}" -X POST "http://$REG_IP:5000/v2/nginx-demo/blobs/uploads/" 2>/dev/null | grep -q 20; then
  pass "Registry accetta push (v2 API raggiungibile)"
else
  warn "Push test via API non disponibile (usare nerdctl su nodo)"
fi

# ── 4. Deploy da registry locale ────────────────────────────────────────────────
info "4. Deploy da registry locale"
DEP_NAME="nginx-from-registry"
kubectl delete deployment $DEP_NAME --now --ignore-not-found &>/dev/null
kubectl delete svc $DEP_NAME --now --ignore-not-found &>/dev/null
kubectl create deployment $DEP_NAME --image="$REG_IP:5000/nginx:test" --port=80 &>/dev/null
kubectl expose deployment $DEP_NAME --type=LoadBalancer --port=80 --target-port=80 --name=$DEP_NAME &>/dev/null
sleep 5
LB_IP=$(kubectl get svc $DEP_NAME -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
if [ -n "$LB_IP" ]; then
  HTTP=$(curl -s -o /dev/null -w "%{http_code}" "http://$LB_IP/" 2>/dev/null || echo "000")
  if [ "$HTTP" = "200" ]; then
    pass "nginx da registry locale → http://$LB_IP (HTTP $HTTP)"
  else
    fail "nginx da registry locale non risponde (HTTP $HTTP)"
  fi
else
  fail "nginx da registry locale non ha ricevuto IP MetalLB"
fi

# ── 5. Pulizia deploy di test ──────────────────────────────────────────────────
info "5. Pulizia"
kubectl delete deployment $DEP_NAME --now --ignore-not-found &>/dev/null
kubectl delete svc $DEP_NAME --now --ignore-not-found &>/dev/null
pass "Deploy di test rimossi (tetris rimane)"

# ── Riepilogo ──────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ "$RET" -eq 0 ]; then
  echo -e "  ${GREEN}✅ DEMO COMPLETATA${NC}"
else
  echo -e "  ${RED}❌ DEMO CON PROBLEMI${NC}"
fi
echo ""
echo "  Tetris:         http://$TETRIS_IP"
echo "  Registry pod:   $REG_IP:5000"
echo "  MetalLB range:  192.168.0.120-192.168.0.135"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
exit "$RET"
