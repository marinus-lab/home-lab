#!/usr/bin/env bash
# Health check completo per il cluster Kubernetes homelab.
# Controlla nodi, componenti core, addon e connettività.
# Restituisce 0 se tutto ok, 1 se ci sono problemi.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
pass()  { echo -e "${GREEN}[PASS]${NC} $*"; }
fail()  { echo -e "${RED}[FAIL]${NC} $*"; RET=1; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
RET=0

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  HEALTH CHECK CLUSTER KUBERNETES"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── 1. kubectl ────────────────────────────────────────────────────────────────
info "1. kubectl"
if command -v kubectl &>/dev/null; then
  pass "kubectl $(kubectl version --client 2>/dev/null | grep -oP 'Client Version: \K\S+')"
else
  fail "kubectl non trovato in PATH"
fi

# ── 2. Kubeconfig ─────────────────────────────────────────────────────────────
info "2. Kubeconfig"
if [ -f ~/.kube/config ]; then
  pass "~/.kube/config presente"
else
  fail "~/.kube/config assente"
fi

# ── 3. API server ─────────────────────────────────────────────────────────────
info "3. API server"
server=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null || true)
if kubectl cluster-info 2>/dev/null | grep -q "control plane"; then
  pass "Raggiungibile: $server"
else
  fail "Non raggiungibile"
fi

# ── 4. Nodi ───────────────────────────────────────────────────────────────────
info "4. Nodi"
nodes=$(kubectl get nodes --no-headers 2>/dev/null || true)
total=$(echo "$nodes" | wc -l)
ready=$(echo "$nodes" | grep -c ' Ready' || true)
echo "  $total nodi, $ready Ready"
for node in $(echo "$nodes" | awk '{print $1}'); do
  st=$(echo "$nodes" | awk -v n="$node" '$1==n{print $2}')
  if [ "$st" = "Ready" ]; then pass "  $node"; else fail "  $node ($st)"; fi
done

# ── 5. Versioni ───────────────────────────────────────────────────────────────
info "5. Versioni"
cli=$(kubectl version --client 2>/dev/null | grep -oP 'Client Version: \K\S+')
srv=$(kubectl version 2>/dev/null | grep -oP 'Server Version: \K\S+')
echo "  Client: ${cli:-N/A}"
echo "  Server: ${srv:-N/A}"

# ── 6. CoreDNS ────────────────────────────────────────────────────────────────
info "6. CoreDNS"
coredns=$(kubectl -n kube-system get pod -l k8s-app=kube-dns --no-headers 2>/dev/null || true)
cr=$(echo "$coredns" | grep -c Running || true)
if [ "$cr" -gt 0 ]; then pass "$cr pod Running"; else fail "Nessun pod Running"; fi

# ── 7. Pod critici kube-system ────────────────────────────────────────────────
info "7. Componenti core"
for label in \
  component=kube-apiserver \
  component=kube-controller-manager \
  component=kube-scheduler \
  k8s-app=kube-proxy \
  k8s-app=calico-node \
  k8s-app=kube-vip; do
  pods=$(kubectl -n kube-system get pod -l "$label" --no-headers 2>/dev/null || true)
  t=$(echo "$pods" | wc -l)
  r=$(echo "$pods" | grep -c Running || true)
  if [ "$t" -gt 0 ] && [ "$t" -eq "$r" ]; then pass "  $label: $r/$r Running"
  else fail "  $label: $r/$t Running"; fi
done

# ── 8. MetalLB ────────────────────────────────────────────────────────────────
info "8. MetalLB"
ctrl=$(kubectl -n metallb-system get pod -l app=metallb,component=controller --no-headers 2>/dev/null | grep -c Running || true)
spk=$(kubectl -n metallb-system get pod -l app=metallb,component=speaker --no-headers 2>/dev/null | grep -c Running || true)
[ "$ctrl" -ge 1 ] && pass "Controller: $ctrl Running" || fail "Controller non Running"
[ "$spk" -ge 1 ] && pass "Speaker: $spk nodi" || warn "Nessuno Speaker"

# ── 9. cert-manager ───────────────────────────────────────────────────────────
info "9. cert-manager"
cm=$(kubectl -n cert-manager get pods --no-headers 2>/dev/null || true)
if [ -n "$cm" ]; then
  t=$(echo "$cm" | wc -l); r=$(echo "$cm" | grep -c Running || true)
  [ "$t" -eq "$r" ] && pass "$r/$r Running" || warn "$r/$t Running"
else
  warn "Non deployato"
fi

# ── 10. Ingress-nginx ─────────────────────────────────────────────────────────
info "10. Ingress-nginx"
ing=$(kubectl -n ingress-nginx get pods --no-headers 2>/dev/null || true)
if [ -n "$ing" ]; then
  t=$(echo "$ing" | wc -l); r=$(echo "$ing" | grep -c Running || true)
  [ "$t" -eq "$r" ] && pass "$r/$r Running" || warn "$r/$t Running"
else
  warn "Non deployato"
fi

# ── 11. Registry ──────────────────────────────────────────────────────────────
info "11. Registry locale"
reg=$(kubectl -n kube-system get pod -l k8s-app=registry --no-headers 2>/dev/null || true)
if [ -n "$reg" ]; then
  r=$(echo "$reg" | grep -c Running || true)
  [ "$r" -ge 1 ] && pass "Running" || warn "Non Running"
else
  warn "Non deployato"
fi

# ── 12. DNS ───────────────────────────────────────────────────────────────────
info "12. DNS interno"
dns_pod=$(kubectl -n kube-system get pod -l k8s-app=kube-dns -o name 2>/dev/null | head -1)
if [ -n "$dns_pod" ]; then
  if kubectl exec -n kube-system "$dns_pod" -- nslookup kubernetes.default.svc.cluster.local &>/dev/null; then
    pass "Risoluzione OK"
  else
    warn "nslookup fallito (potrebbe mancare nel container)"
  fi
else
  fail "Nessun pod CoreDNS"
fi

# ── 13. Panoramica ────────────────────────────────────────────────────────────
info "13. Pod totali"
all=$(kubectl get pods -A --no-headers 2>/dev/null | wc -l)
run=$(kubectl get pods -A --no-headers 2>/dev/null | grep -c Running || true)
echo "  $run/$all pod Running"
echo ""

# ── 14. StorageClass ──────────────────────────────────────────────────────────
info "14. StorageClass"
sc=$(kubectl get storageclass --no-headers 2>/dev/null || true)
if [ -n "$sc" ]; then
  echo "$sc" | while read -r line; do
    echo "  $(echo "$line" | awk '{print $1}') ($(echo "$line" | awk '{print $2}'))"
  done
else
  warn "Nessuna StorageClass"
fi

# ── Riepilogo ─────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ "$RET" -eq 0 ]; then
  echo -e "  ${GREEN}✅ CLUSTER SANO${NC}"
else
  echo -e "  ${RED}❌ CLUSTER CON PROBLEMI ($RET check falliti)${NC}"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
exit "$RET"
