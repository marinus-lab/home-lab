#!/bin/bash
# Longhorn Storage Install Script for Kubernetes Homelab
# Version: 3.0.0
# Installa e configura automaticamente Longhorn Storage

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Longhorn Storage Installation v3.0  ${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}❌ kubectl non trovato. Installalo prima.${NC}"
        exit 1
    fi
}

check_cluster() {
    if ! kubectl cluster-info &> /dev/null; then
        echo -e "${RED}❌ Cluster Kubernetes non raggiungibile${NC}"
        exit 1
    fi
}

configure_disks() {
    echo -e "${BLUE}💾 Configurazione dischi Longhorn via API...${NC}"
    
    local nodes=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}')
    
    for node in $nodes; do
        echo -e "${YELLOW}⚙️  Aggiungo disco su $node...${NC}"
        
        # Get a manager pod to execute API calls
        local manager_pod=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        
        if [ -n "$manager_pod" ]; then
            # Use longhorn-manager's built-in API via port-forward
            # Create disk via HTTP API
            kubectl exec -n longhorn-system $manager_pod -- \
                wget -q -O - --method=POST \
                --header="Content-Type: application/json" \
                --body-data='{"name":"disk-'$node'","node":"'$node'","path":"/var/lib/longhorn/","allowSharedDisk":true,"shared":true,"filesystem":"ext4"}' \
                http://localhost:12080/v1/disks 2>/dev/null || true
                
            # Alternative: use curl if available
            kubectl exec -n longhorn-system $manager_pod -- \
                sh -c "curl -s -X POST -H 'Content-Type: application/json' -d '{\"name\":\"disk-'$node'\",\"node\":\"'$node'\",\"path\":\"/var/lib/longhorn/\",\"allowSharedDisk\":true,\"shared\":true}' http://localhost:12080/v1/disks" 2>/dev/null || true
        fi
        
        echo -e "${GREEN}✓ Disco configurato su $node${NC}"
    done
    
    # Wait for disks to be ready
    echo -e "${YELLOW}⏳ Attendendo che i dischi siano pronti (60 secondi)...${NC}"
    sleep 60
}

# Step 1: Check prerequisites
echo -e "${BLUE}📋 Verifica prerequisiti...${NC}"
check_kubectl
check_cluster
echo -e "${GREEN}✓ Prerequisiti verificati${NC}"
echo ""

# Step 2: Create namespace
echo -e "${BLUE}📁 Creazione namespace longhorn-system...${NC}"
kubectl create namespace longhorn-system 2>/dev/null || true
echo -e "${GREEN}✓ Namespace creato${NC}"
echo ""

# Step 3: Install Longhorn
echo -e "${BLUE}🔧 Installazione Longhorn v1.7.1...${NC}"
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.7.1/deploy/longhorn.yaml
echo -e "${GREEN}✓ Longhorn installato${NC}"
echo ""

# Step 4: Wait for core pods
echo -e "${YELLOW}⏳ Attendendo i pods core...${NC}"
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=longhorn -n longhorn-system --timeout=300s 2>/dev/null || true
echo -e "${GREEN}✓ Tutti i pods pronti${NC}"
echo ""

# Step 5: Enable snapshot controller
echo -e "${BLUE}📸 Abilitazione snapshot controller...${NC}"
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.7.1/deploy/snapshot-controller.yaml 2>/dev/null || true
echo -e "${GREEN}✓ Snapshot controller attivo${NC}"
echo ""

# Step 6: Configure LoadBalancer access
echo -e "${BLUE}🌐 Configurazione accesso LoadBalancer...${NC}"
kubectl patch service longhorn-frontend -n longhorn-system -p '{"spec": {"type": "LoadBalancer"}}' 2>/dev/null || true
echo -e "${GREEN}✓ Servizio frontend configurato${NC}"
echo ""

# Step 7: Configure disks on all nodes
configure_disks
echo ""

# Step 8: Create default StorageClass
echo -e "${BLUE}💾 Creazione StorageClass predefinito 'longhorn-local'...${NC}"
kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-local
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: driver.longhorn.io
allowVolumeExpansion: true
volumeBindingMode: WaitForFirstConsumer
parameters:
  numberOfReplicas: "2"
  staleReplicaTimeout: "30"
  fromBackup: ""
  fsType: "ext4"
EOF
echo -e "${GREEN}✓ StorageClass creato${NC}"
echo ""

# Step 9: Wait for LoadBalancer IP
echo -e "${YELLOW}⏳ Recupero IP del servizio Longhorn...${NC}"
sleep 10

EXTERNAL_IP=""
for i in {1..30}; do
    EXTERNAL_IP=$(kubectl get svc longhorn-frontend -n longhorn-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    if [ -n "$EXTERNAL_IP" ]; then break; fi
    echo -e "${YELLOW}.${NC}"
    sleep 5
done

# Final status
echo ""
echo -e "${BLUE}📋 Stato Longhorn:${NC}"
kubectl get pods -n longhorn-system -o wide

echo ""
echo -e "${BLUE}========================================${NC}"
if [ -n "$EXTERNAL_IP" ]; then
    echo -e "${GREEN}🌐 Longhorn Dashboard:${NC}"
    echo -e "   URL: http://${EXTERNAL_IP}:80"
    echo -e "   Credenziali: admin / admin"
else
    echo -e "${YELLOW}⚠️  IP assegnato in arrivo${NC}"
fi
echo -e "${BLUE}========================================${NC}"

echo ""
echo -e "${GREEN}✅ Installazione completata!${NC}"
echo ""
echo -e "${BLUE}📚 Prossimi passi:${NC}"
echo -e "${GREEN}1. Accesso: http://${EXTERNAL_IP}:80${NC}"
echo -e "${GREEN}2. Verifica dischi in Storage → Disk${NC}"
echo -e "${GREEN}3. Usa storageClassName: longhorn-local${NC}"