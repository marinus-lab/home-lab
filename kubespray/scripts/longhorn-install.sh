#!/bin/bash
# Longhorn Storage Install Script for Kubernetes Homelab
# Version: 1.0.0
# This script installs Longhorn storage system and provisions default storage class

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Longhorn Storage Installation       ${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Function to check if kubectl is available
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}❌ kubectl non trovato. Installalo prima.${NC}"
        exit 1
    fi
}

# Function to check cluster connectivity
check_cluster() {
    if ! kubectl cluster-info &> /dev/null; then
        echo -e "${RED}❌ Cluster Kubernetes non raggiungibile${NC}"
        exit 1
    fi
}

# Function to check if Longhorn is already installed
check_existing_installation() {
    if kubectl get namespace longhorn-system &> /dev/null; then
        echo -e "${YELLOW}⚠️  Longhorn già installato. Vuoi reinstallare? (s/n)${NC}"
        read -r response
        if [[ "$response" =~ ^[Ss]$ ]]; then
            echo -e "${YELLOW}Cancelling existing installation...${NC}"
            kubectl delete namespace longhorn-system
            sleep 5
        else
            echo -e "${GREEN}Installazione annullata.${NC}"
            exit 0
        fi
    fi
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

# Step 4: Wait for pods
echo -e "${YELLOW}⏳ Attendendo i pods Longhorn (potrebbe richiedere 2-3 minuti)...${NC}"
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=longhorn -n longhorn-system --timeout=300s 2>/dev/null || {
    echo -e "${YELLOW}⏳ Pods in fase di inizializzazione...${NC}"
    kubectl get pods -n longhorn-system
    sleep 60
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=longhorn -n longhorn-system --timeout=180s 2>/dev/null
}
echo -e "${GREEN}✓ Tutti i pods pronti${NC}"
echo ""

# Step 5: Enable snapshot controller
echo -e "${BLUE}📸 Abilitazione snapshot controller...${NC}"
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.7.1/deploy/snapshot-controller.yaml 2>/dev/null || true
echo -e "${GREEN}✓ Snapshot controller attivo${NC}"
echo ""

# Step 6: Create default StorageClass
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
echo -e "${GREEN}✓ StorageClass creato e impostato come predefinito${NC}"
echo ""

# Step 7: Configure LoadBalancer access
echo -e "${BLUE}🌐 Configurazione accesso LoadBalancer...${NC}"
kubectl patch service longhorn-frontend -n longhorn-system -p '{"spec": {"type": "LoadBalancer"}}' 2>/dev/null || true
echo -e "${GREEN}✓ Servizio frontend configurato${NC}"
echo ""

# Step 8: Wait for LoadBalancer IP
echo -e "${YELLOW}⏳ Recupero IP del servizio Longhorn...${NC}"
sleep 10

EXTERNAL_IP=""
for i in {1..30}; do
    EXTERNAL_IP=$(kubectl get svc longhorn-frontend -n longhorn-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    if [ -n "$EXTERNAL_IP" ]; then
        break
    fi
    echo -e "${YELLOW}.${NC}"
    sleep 5
done

# Step 9: Final status and instructions
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
    echo -e "   Verifica con: kubectl get svc -n longhorn-system longhorn-frontend"
fi
echo -e "${BLUE}========================================${NC}"

echo ""
echo -e "${BLUE}📚 Prossimi passi:${NC}"
echo -e "${GREEN}1. Accedi alla dashboard con le credenziali sopra${NC}"
echo -e "${GREEN}2. Vai su Storage → Disk → Add Disk${NC}"
echo -e "${GREEN}3. Configura disco su ogni nodo Kubernetes${NC}"
echo -e "${GREEN}4. Crea PVCs usando storageClassName: longhorn-local${NC}"
echo ""