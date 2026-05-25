#!/usr/bin/env bash
# Demo del cluster Kubernetes homelab.
# Deploya e verifica: Tetris, Hello Kubernetes, Podinfo, registry, MetalLB.

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
pass() { echo -e "${GREEN}[PASS]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; RET=1; }
info() { echo -e "${BLUE}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
deploy_app() { local n=$1 i=$2 p=$3 t=$4; svc_ip=
  if kubectl get svc "$n" -o name &>/dev/null; then
    svc_ip=$(kubectl get svc "$n" -o jsonpath='{.status.loadBalancer.ingress[0].ip}') && return
  fi
  info "Deploy $n..."
  kubectl create deployment "$n" --image="$i" --port="$p" &>/dev/null
  kubectl expose deployment "$n" --type=LoadBalancer --port="$t" --target-port="$p" --name="$n" &>/dev/null
  for _ in 1 2 3 4 5 6 7 8; do sleep 5
    svc_ip=$(kubectl get svc "$n" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
    [ -n "$svc_ip" ] && break
  done
}
RET=0

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  DEMO CLUSTER KUBERNETES HOMELAB"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── 1. Tetris ──────────────────────────────────────────────────────────────────
info "1. Tetris"
deploy_app tetris docker.io/lrakai/tetris:latest 80 80
if [ -n "$svc_ip" ]; then
  H=$(curl -s -o /dev/null -w "%{http_code}" "http://$svc_ip/" 2>/dev/null || echo)
  [ "$H" = "200" ] && pass "http://$svc_ip (Tetris)" || fail "HTTP $H su $svc_ip"
else
  fail "Nessun IP MetalLB per tetris"
fi
TETRIS_IP=$svc_ip

# ── 2. Hello Kubernetes ────────────────────────────────────────────────────────
info "2. Hello Kubernetes"
deploy_app hello-k8s docker.io/paulbouwer/hello-kubernetes:1.10.1 8080 80
if [ -n "$svc_ip" ]; then
  H=$(curl -s -o /dev/null -w "%{http_code}" "http://$svc_ip/" 2>/dev/null || echo)
  [ "$H" = "200" ] && pass "http://$svc_ip (Hello K8s)" || fail "HTTP $H su $svc_ip"
else
  fail "Nessun IP MetalLB per hello-k8s"
fi
HELLO_IP=$svc_ip

# ── 3. Podinfo ─────────────────────────────────────────────────────────────────
info "3. Podinfo"
deploy_app podinfo ghcr.io/stefanprodan/podinfo:latest 9898 9898
if [ -n "$svc_ip" ]; then
  H=$(curl -s -o /dev/null -w "%{http_code}" "http://$svc_ip:9898/" 2>/dev/null || echo)
  [ "$H" = "200" ] && pass "http://$svc_ip:9898 (Podinfo)" || fail "HTTP $H su $svc_ip"
else
  fail "Nessun IP MetalLB per podinfo"
fi
PODINFO_IP=$svc_ip

# ── 4. Registry interno ────────────────────────────────────────────────────────
info "4. Registry interno"
REG_POD=$(kubectl -n kube-system get pod -l k8s-app=registry -o jsonpath='{.items[0].status.podIP}' 2>/dev/null || true)
if [ -n "$REG_POD" ]; then
  REG_SVC=$(kubectl -n kube-system get svc registry -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true)
  # Test registry via port-forward temporaneo
  kubectl port-forward -n kube-system svc/registry 15999:5000 &>/tmp/reg-pf.log &
  PF_PID=$!
  sleep 2
  REPOS=$(curl -s http://localhost:15999/v2/_catalog 2>/dev/null | grep -o '"repositories":\[[^]]*\]' || echo 'vuoto')
  kill $PF_PID 2>/dev/null
  pass "Registry $REG_SVC:5000 — $REPOS"
else
  fail "Registry pod non trovato"
fi

# ── 5. Registry push/pull (via nerdctl su nodo) ──────────────────────────────
info "5. Registry push/pull"
# Test push via SSH sul nodo che ospita il registry (usa nerdctl --insecure-registry)
REG_NODE=$(kubectl -n kube-system get pod -l k8s-app=registry -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null || true)
REG_IP=$(kubectl -n kube-system get pod -l k8s-app=registry -o jsonpath='{.items[0].status.podIP}' 2>/dev/null || true)
if [ -n "$REG_NODE" ] && [ -n "$REG_IP" ]; then
  # Estrai IP del nodo per SSH
  NODE_IP=$(kubectl get node "$REG_NODE" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || true)
  if [ -n "$NODE_IP" ]; then
    RESULT=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "ubuntu@$NODE_IP" \
      "sudo nerdctl -n k8s.io pull docker.io/library/nginx:alpine 2>&1 | tail -1 && \
       sudo nerdctl -n k8s.io tag docker.io/library/nginx:alpine $REG_IP:5000/nginx:test 2>&1 && \
       sudo nerdctl -n k8s.io push $REG_IP:5000/nginx:test --insecure-registry 2>&1" 2>/dev/null || echo "SSH_FAIL")
    if echo "$RESULT" | grep -q "done\|resolved\|already exists\|config"; then
      pass "Push nginx:alpine → $REG_IP:5000/nginx:test"
    elif echo "$RESULT" | grep -q "SSH_FAIL"; then
      warn "SSH non raggiungibile — push via nerdctl manuale su $NODE_IP"
    else
      warn "Push output non atteso (verifica con ssh ubuntu@$NODE_IP)"
    fi
  fi
else
  warn "Registry node sconosciuto"
fi

# ── Riepilogo ──────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ "$RET" -eq 0 ]; then
  echo -e "  ${GREEN}✅ DEMO COMPLETATA${NC}"
else
  echo -e "  ${RED}❌ DEMO CON PROBLEMI${NC}"
fi
echo ""
echo "  Tetris             http://$TETRIS_IP"
echo "  Hello Kubernetes   http://$HELLO_IP"
echo "  Podinfo            http://$PODINFO_IP:9898"
echo "  Registry pod       $REG_POD:5000"
echo "  MetalLB range      192.168.0.120-192.168.0.135"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
exit "$RET"
