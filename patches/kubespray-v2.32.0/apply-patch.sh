#!/usr/bin/env bash
# Patch per Kubespray v2.32.0 — risolve:
# 1. "specifying a root certificates file with the insecure flag is not allowed"
#    (rimozione difensiva: presente solo in alcune build di cluster_roles)
# 2. Timeout su "Wait for new control plane nodes to be Ready" quando il CNI
#    (calico) viene installato in un play successivo: ignore_errors sul wait.
# NOTA: NON toccare i blocchi shell/changed_when di kubeadm-setup.yml — sono
# task legittimi (es. "Create hardcoded kubeadm token") e cancellarli con sed
# corrompe il YAML ("no module/action detected in task").
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

# Aggiunge ALLOW_BROKEN_CONDITIONALS per il ruolo registry (v2.32.0)
# Il defaults/main.yml usa registry_storage_class: "" che con ansible-core 2.19
# crea un conditional rotto (str invece di boolean).
REGISTRY_DEFAULTS="$KUBESPRAY_DIR/roles/kubernetes-apps/registry/defaults/main.yml"
if [ -f "$REGISTRY_DEFAULTS" ]; then
  if grep -q 'registry_storage_class: ""' "$REGISTRY_DEFAULTS"; then
    echo "Applicando patch v2.32.0: correggo registry_storage_class in $REGISTRY_DEFAULTS..."
    sed -i 's/registry_storage_class: ""/registry_storage_class: none/' "$REGISTRY_DEFAULTS"
    echo "Patch registry applicata."
  else
    echo "Patch v2.32.0: $REGISTRY_DEFAULTS non usa stringa vuota (ok)"
  fi
else
  echo "Patch v2.32.0: $REGISTRY_DEFAULTS non trovato"
fi

# Aggiunge ignore_errors: true al task "Wait for new control plane nodes to be Ready"
# Il CNI calico viene installato nei play kubernetes-apps SUCCESSIVI a questo wait:
# su un cluster inzio i master restano NotReady e il task fallirebbe per sempre.
SECONDARY_FILE="$KUBESPRAY_DIR/roles/kubernetes/control-plane/tasks/kubeadm-secondary.yml"
if [ -f "$SECONDARY_FILE" ]; then
  # Cerchiamo la riga esatta del nome del task
  if grep -q '^- name: Wait for new control plane nodes to be Ready$' "$SECONDARY_FILE"; then
    # Verifichiamo se ignore_errors è già presente per evitare duplicazioni
    if ! grep -A1 '^- name: Wait for new control plane nodes to be Ready$' "$SECONDARY_FILE" | grep -q 'ignore_errors: true'; then
      echo "Applicando patch v2.32.0: aggiungo ignore_errors a Wait for new control plane nodes to be Ready..."
      # Usiamo sed per inserire la nuova linea dopo la linea del nome del task
      sed -i '/^- name: Wait for new control plane nodes to be Ready$/a \  ignore_errors: true' "$SECONDARY_FILE"
      echo "Patch kubeadm-secondary.yml applicata."
    else
      echo "Patch v2.32.0: kubeadm-secondary.yml ha già ignore_errors (ok)"
    fi
  else
    echo "Patch v2.32.0: il task 'Wait for new control plane nodes to be Ready' non trovato in $SECONDARY_FILE"
  fi
else
  echo "Patch v2.32.0: $SECONDARY_FILE non trovato"
fi
