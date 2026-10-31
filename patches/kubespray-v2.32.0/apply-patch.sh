#!/usr/bin/env bash
# Patch per Kubespray v2.32.0 — risolve:
# "specifying a root certificates file with the insecure flag is not allowed"
# nel ruolo kubernetes-apps/cluster_roles/tasks/main.yml
# e nel ruolo kubernetes/control-plane/tasks/kubeadm-setup.yml (admin.conf con insecure-skip)
set -euo pipefail

KUBESPRAY_DIR="${KUBESPRAY_DIR:-$HOME/kubespray}"

# Rimuove --insecure-skip-tls-verify dalla riga kubectl apply nel ruolo cluster_roles
PATCH_FILE="$KUBESPRAY_DIR/roles/kubernetes-apps/cluster_roles/tasks/main.yml"
if [ -f "$PATCH_FILE" ]; then
  if grep -q 'insecure-skip-tls-verify' "$PATCH_FILE"; then
    echo "Applicando patch v2.32.0: rimuovo --insecure-skip-tls-verify da $PATCH_FILE"
    sed -i 's/--insecure-skip-tls-verify //' "$PATCH_FILE"
    echo "Patch cluster_roles applicata."
  else
    echo "Patch v2.32.0: $PATCH_FILE non contiene --insecure-skip-tls-verify (ok)"
  fi
else
  echo "Patch v2.32.0: $PATCH_FILE non trovato (clone Kubespray potrebbe non contenere il ruolo)"
fi

# Rimuove insecure-skip-tls-verify da admin.conf sul clone (interferisce con kubeadm token create)
ADMIN_CONF_FILE="$KUBESPRAY_DIR/roles/kubernetes/control-plane/tasks/kubeadm-setup.yml"
if [ -f "$ADMIN_CONF_FILE" ]; then
  if grep -q 'insecure-skip-tls-verify' "$ADMIN_CONF_FILE"; then
    echo "Applicando patch v2.32.0: rimuovo insecure-skip-tls-verify da kubeadm-setup.yml..."
    sed -i '/insecure-skip-tls-verify/d' "$ADMIN_CONF_FILE"
    echo "Patch kubeadm-setup.yml applicata."
  else
    echo "Patch v2.32.0: kubeadm-setup.yml non contiene insecure-skip-tls-verify (ok)"
  fi
else
  echo "Patch v2.32.0: $ADMIN_CONF_FILE non trovato (clone Kubespray potrebbe non contenere il ruolo)"
fi
