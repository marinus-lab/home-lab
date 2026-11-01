#!/usr/bin/env bash
# Patch per Kubespray v2.32.0 (ansible-core 2.19) — risolve:
# 1. "specifying a root certificates file with the insecure flag is not allowed"
#    (rimozione difensiva: presente solo in alcune build di cluster_roles)
# 2. Conditionals non booleani nel ruolo registry: in ansible-core 2.19 un
#    when: che valuta a stringa è un ERRORE. Kubespray usa
#      registry_storage_class != none and registry_storage_class
#    che, con valore "local-path", valuta a stringa → "Conditional result (True)
#    was derived from value of type 'str'". Riscritti in predicati booleani.
# NOTA: NON toccare i blocchi shell/changed_when di kubeadm-setup.yml — sono
# task legittimi (es. "Create hardcoded kubeadm token") e cancellarli con sed
# corrompe il YAML ("no module/action detected in task").
# NOTA: niente ignore_errors — se un task fallisce deve fallire il deploy
# (mascherare non è un fix; VIP 192.168.0.80 è raggiungibile dalla v2.32.0+fix).
set -euo pipefail

KUBESPRAY_DIR="${KUBESPRAY_DIR:-$HOME/kubespray}"

# 1) Rimuove --insecure-skip-tls-verify dalla riga kubectl apply nel ruolo cluster_roles
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

# 2) Conditionals registry → booleani (ansible-core 2.19)
# "X != none and X" restituisce la stringa X se vera; sostituito con
# "X not in (none, '')" che restituisce sempre un bool.
REGISTRY_TASKS="$KUBESPRAY_DIR/roles/kubernetes-apps/registry/tasks/main.yml"
if [ -f "$REGISTRY_TASKS" ]; then
  if grep -q 'registry_storage_class != none and registry_storage_class' "$REGISTRY_TASKS"; then
    echo "Applicando patch v2.32.0: conditionals registry booleani in $REGISTRY_TASKS"
    sed -i 's/registry_storage_class != none and registry_storage_class/registry_storage_class not in (none, "")/' "$REGISTRY_TASKS"
    sed -i 's/registry_disk_size != none and registry_disk_size/registry_disk_size not in (none, "")/' "$REGISTRY_TASKS"
    # Verifica: nessun conditional stringa residuo
    if grep -q '!= none and registry_' "$REGISTRY_TASKS"; then
      echo "ERRORE patch v2.32.0: conditionals registry rimasti non booleani" >&2
      exit 1
    fi
    echo "Patch registry applicata (booleana)."
  else
    echo "Patch v2.32.0: conditionals registry già booleani o task assente (ok)"
  fi
else
  echo "Patch v2.32.0: $REGISTRY_TASKS non trovato"
fi
