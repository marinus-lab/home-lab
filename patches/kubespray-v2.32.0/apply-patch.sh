#!/usr/bin/env bash
# Patch per Kubespray v2.32.0 — risolve:
# 1. "specifying a root certificates file with the insecure flag is not allowed"
# 2. Timeout su "Wait for new control plane nodes to be Ready" prima che CNI sia installato
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
  echo "Patch v2.32.0: $PATCH_FILE non trovato"
fi

# Rimuove insecure-skip-tls-verify da kubeadm-setup.yml
ADMIN_CONF_FILE="$KUBESPRAY_DIR/roles/kubernetes/control-plane/tasks/kubeadm-setup.yml"
if [ -f "$ADMIN_CONF_FILE" ]; then
  if grep -q 'insecure-skip-tls-verify' "$ADMIN_CONF_FILE"; then
    echo "Applicando patch v2.32.0: rimuovo insecure-skip-tls-verify da kubeadm-setup.yml..."
    sed -i '/insecure-skip-tls-verify/d' "$ADMIN_CONF_FILE"
    echo "Patch kubeadm-setup.yml applicata."
  fi
  if grep -q '^  shell: >-$' "$ADMIN_CONF_FILE"; then
    echo "Applicando patch v2.32.0: rimuovo residui blocco shell da kubeadm-setup.yml..."
    sed -i '/^  shell: >-$/,/changed_when: false$/d' "$ADMIN_CONF_FILE"
    echo "Residui blocco shell rimossi."
  fi
else
  echo "Patch v2.32.0: $ADMIN_CONF_FILE non trovato"
fi

# Aggiunge ignore_errors: true al task "Wait for new control plane nodes to be Ready" in kubeadm-secondary.yml
SECONDARY_FILE="$KUBESPRAY_DIR/roles/kubernetes/control-plane/tasks/kubeadm-secondary.yml"
if [ -f "$SECONDARY_FILE" ]; then
  if grep -q 'Wait for new control plane nodes to be Ready' "$SECONDARY_FILE"; then
    if ! grep -q 'ignore_errors: true' "$SECONDARY_FILE"; then
      echo "Applicando patch v2.32.0: aggiungo ignore_errors a Wait for new control plane nodes to be Ready..."
      sed -i '/name: Wait for new control plane nodes to be Ready/a \  ignore_errors: true' "$SECONDARY_FILE"
      echo "Patch kubeadm-secondary.yml applicata."
    else
      echo "Patch v2.32.0: kubeadm-secondary.yml ha già ignore_errors (ok)"
    fi
  fi
else
  echo "Patch v2.32.0: $SECONDARY_FILE non trovato"
fi
