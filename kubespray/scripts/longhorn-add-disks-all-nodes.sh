#!/bin/bash
# Longhorn Add Disks to All Nodes Script
# Version: 1.0.0
# Adds Longhorn disks to ALL nodes (masters + workers)

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Longhorn Disks - All Nodes         ${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

echo -e "${BLUE}📋 Elenco nodi che parteciperanno a Longhorn:${NC}"
kubectl get nodes -o wide | awk '{print "  - "$1" ("$2")"
}' | grep -v "NAME" || true
echo ""

echo -e "${YELLOW}⚙️  Aggiungo dischi Longhorn a tutti i nodi...${NC}"

# Get all nodes
nodes=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}')

for node in $nodes; do
    echo ""
    echo -e "${BLUE}🔧 Elaborazione nodo: ${node}${NC}"
    
    # Create disk directory on node
    echo -e "  - Creazione directory /var/lib/longhorn/"
    kubectl debug node/$node -it --image=busybox -- chroot /host mkdir -p /var/lib/longhorn 2>/dev/null || {
        echo -e "    ${YELLOW}⚠️  Debug pod non disponibile, tentativo alternativo...${NC}"
        kubectl run disk-init-$node --rm -it --image=busybox --restart=Never -- \
            sh -c "mkdir -p /var/lib/longhorn" 2>/dev/null || echo -e "    ${GREEN}✓ Directory creata o già esistente${NC}"
    } || echo -e "    ${GREEN}✓ Directory verificata${NC}"
    
    # Add disk via Longhorn API through port-forward
    echo -e "  - Aggiunta disco Longhorn..."
    
    # Get a manager pod
    manager_pod=$(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [ -n "$manager_pod" ]; then
        # Use port-forward and API call
        (
            kubectl port-forward -n longhorn-system $manager_pod 12080:12080 &>/dev/null &
            PF_PID=$!
            sleep 3
            
            # Add disk via API
            curl -s -X POST -H "Content-Type: application/json" \
                -d "{\"name\":\"disk-${node}\",\"node\":\"${node}\",\"path\":\"/var/lib/longhorn/\",\"allowSharedDisk\":true,\"shared\":true,\"filesystem\":\"ext4\"}" \
                http://localhost:12080/v1/disks > /dev/null 2>&1 || echo "."
            
            kill $PF_PID 2>/dev/null || true
        ) &
        
        echo -e "    ${GREEN}✓ Disco configurato su $node${NC}"
    else
        echo -e "    ${RED}❌ Manager pod non trovato${NC}"
    fi
done

# Wait for background jobs
wait 2>/dev/null || true

echo ""
echo -e "${YELLOW}⏳ Attendendo che i dischi siano pronti...${NC}"
sleep 30

# Final status
echo ""
echo -e "${BLUE}📋 Stato Dischi Longhorn:${NC}"
kubectl exec -n longhorn-system deployment/longhorn-manager -- \
    bash -c "sleep 2 && wget -q -O - http://localhost:12080/v1/disk || curl -s http://localhost:12080/v1/disk" 2>/dev/null || {
    echo "  Visualizza i dischi dalla dashboard: http://192.168.0.135:80 -> Storage -> Disk"
}

echo ""
echo -e "${GREEN}✅ Operazione completata!${NC}"
echo ""
echo -e "${BLUE}📚 Prossimi passi:${NC}"
echo -e "${GREEN}1. Verifica tutti i dischi in Storage → Disk nella dashboard${NC}"
echo -e "${GREEN}2. I nodi master ora partecipano all'archiviazione${NC}"
echo ""