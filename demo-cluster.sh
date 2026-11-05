#!/usr/bin/env bash
# Demo del cluster Kubernetes homelab.
# Deploya e verifica: Tetris, Hello Kubernetes, Podinfo, Registry, MetalLB, Three.js Boat.
#

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
pass() { echo -e "${GREEN}[PASS]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*" ; RET=1; }
info() { echo -e "${BLUE}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }

# Funzione per deployare app e attendere IP MetalLB
deploy_app() {
  local name=$1 image=$2 pod_port=$3 svc_port=$4
  svc_ip=""

  if kubectl get svc "$name" -o name &>/dev/null 2>&1; then
    svc_ip=$(kubectl get svc "$name" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
    [ -n "$svc_ip" ] && return 0
  fi

  info "Deploy $name..."
  kubectl create deployment "$name" --image="$image" --port="$pod_port" &>/dev/null 2>&1
  kubectl expose deployment "$name" --type=LoadBalancer --port="$svc_port" --target-port="$pod_port" --name="$name" &>/dev/null 2>&1

  for i in $(seq 1 20); do
    sleep 3
    svc_ip=$(kubectl get svc "$name" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
    [ -n "$svc_ip" ] && return 0
  done
}

check_http() {
  local url=$1 expected=$2
  H=$(curl -s -o /dev/null -w "%{http_code}" "$url" --connect-timeout 5 2>/dev/null || echo "000")
  [ "$H" = "$expected" ]
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
  check_http "http://$svc_ip/" "200" && pass "http://$svc_ip (Tetris)" || fail "HTTP su $svc_ip"
else fail "Nessun IP MetalLB per tetris"; fi
TETRIS_IP=$svc_ip

# ── 2. Hello Kubernetes ────────────────────────────────────────────────────────
info "2. Hello Kubernetes"
deploy_app hello-k8s docker.io/paulbouwer/hello-kubernetes:1.11 8080 80
if [ -n "$svc_ip" ]; then
  check_http "http://$svc_ip/" "200" && pass "http://$svc_ip (Hello K8s)" || fail "HTTP su $svc_ip"
else fail "Nessun IP MetalLB per hello-k8s"; fi
HELLO_IP=$svc_ip

# ── 3. Podinfo ─────────────────────────────────────────────────────────────────
info "3. Podinfo"
deploy_app podinfo ghcr.io/stefanprodan/podinfo:latest 9898 9898
if [ -n "$svc_ip" ]; then
  check_http "http://$svc_ip:9898/" "200" && pass "http://$svc_ip:9898 (Podinfo)" || fail "HTTP su $svc_ip"
else fail "Nessun IP MetalLB per podinfo"; fi
PODINFO_IP=$svc_ip

# ── 4. Registry interno ────────────────────────────────────────────────────────
info "4. Registry interno"
REG_POD=$(kubectl -n kube-system get pod -l k8s-app=registry -o jsonpath='{.items[0].status.podIP}' 2>/dev/null || true)
REG_STATUS=$(kubectl -n kube-system get pod -l k8s-app=registry -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Pending")

if [ -n "$REG_POD" ] && [ "$REG_STATUS" = "Running" ]; then
  REG_SVC=$(kubectl -n kube-system get svc registry -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true)
  kubectl port-forward -n kube-system svc/registry 15999:5000 &>/tmp/reg-pf.log &
  PF_PID=$!
  sleep 2
  REPOS=$(curl -s http://localhost:15999/v2/_catalog 2>/dev/null | grep -o '"repositories":\[[^]]*\]' || echo 'vuoto')
  kill $PF_PID 2>/dev/null
  pass "Registry $REG_SVC:5000 — $REPOS"
else
  warn "Registry pod in stato '$REG_STATUS' — necessita PVC (saltato)"
fi

# ── 5. Registry push/pull (via nerdctl su nodo) ──────────────────────────────
info "5. Registry push/pull"
REG_NODE=$(kubectl -n kube-system get pod -l k8s-app=registry -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null || true)
REG_IP=$(kubectl -n kube-system get pod -l k8s-app=registry -o jsonpath='{.items[0].status.podIP}' 2>/dev/null || true)
if [ -n "$REG_NODE" ] && [ -n "$REG_IP" ]; then
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

# ── 6. Three.js Boat Simulator ───────────────────────────────────────────────
info "6. Three.js Boat Simulator"
# Crea deployment nginx vuoto (se non esiste)
kubectl create deployment boat-sim --image=nginx --port=80 &>/dev/null 2>&1 || true

# Crea ConfigMap con l'HTML Three.js
cat > /tmp/boat-index.html << 'HTMLEOF'
<!DOCTYPE html>
<html><head><title>Boat Simulator</title></head>
<body style="margin:0;background:#001133">
<canvas id="c"></canvas>
<script src="https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js"></script>
<script>
const c = document.getElementById('c'), ctx = c.getContext('webgl');
c.width = window.innerWidth; c.height = window.innerHeight;
const scene = new THREE.Scene(), cam = new THREE.PerspectiveCamera(75, c.width/c.height, 0.1, 1000),
boat = new THREE.Mesh(new THREE.BoxGeometry(2,1,4), new THREE.MeshBasicMaterial({color:0x0066cc}));
scene.add(boat); scene.add(new THREE.AmbientLight(0xffffff, 0.5));
cam.position.z = 8;
function animate() {
  requestAnimationFrame(animate);
  boat.rotation.y += 0.02;
  boat.position.y = 0.5 * Math.sin(Date.now()*0.005);
  ctx.render(scene, cam);
}
animate();
</script></body></html>
HTMLEOF

# Sostituisci l'index.html nel pod
kubectl delete configmap boat-html -n default &>/dev/null || true
kubectl create configmap boat-html --from-file=index.html=/tmp/boat-index.html -n default &>/dev/null || true

# Aggiorna il deployment per usare il ConfigMap
kubectl set volume deploy/boat-sim --name=html --configmap-name=boat-html --mount-path=/usr/share/nginx/html --overwrite &>/dev/null || true

# Se il set volume non funziona, copia direttamente nel pod
POD_NAME=$(kubectl get pods -l app=boat-sim -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -n "$POD_NAME" ]; then
  kubectl cp /tmp/boat-index.html $POD_NAME:/usr/share/nginx/html/index.html -c nginx 2>/dev/null || true
fi

kubectl expose deployment boat-sim --type=LoadBalancer --port=80 --name=boat-sim &>/dev/null 2>&1
sleep 5
svc_ip=$(kubectl get svc boat-sim -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
if [ -n "$svc_ip" ]; then
  check_http "http://$svc_ip/" "200" && pass "http://$svc_ip (Three.js Boat)" || fail "HTTP su $svc_ip"
else fail "Nessun IP MetalLB per boat-sim"; fi
BOAT_IP=$svc_ip

# ── Riepilogo ──────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ "$RET" -eq 0 ]; then echo -e "  ${GREEN}✅ DEMO COMPLETATA${NC}"; else echo -e "  ${RED}❌ DEMO CON PROBLEMI${NC}"; fi
echo ""
echo "  Tetris             http://$TETRIS_IP"
echo "  Hello Kubernetes   http://$HELLO_IP"
echo "  Podinfo            http://$PODINFO_IP:9898"
echo "  Registry pod       $REG_POD:5000"
echo "  Three.js Boat      http://$BOAT_IP"
MLB_NET="${TETRIS_IP%.*}"
[ -n "$MLB_NET" ] && echo "  MetalLB range      $MLB_NET.120-$MLB_NET.135"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
exit "$RET"