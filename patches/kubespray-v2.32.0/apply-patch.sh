#!/usr/bin/env bash
# Patch per Kubespray v2.32.0 — risolve:
# "specifying a root certificates file with the insecure flag is not allowed"
# nel ruolo kubernetes-apps/cluster_roles/tasks/main.yml
set -euo pipefail

KUBESPRAY_DIR="${KUBESPRAY_DIR:-$HOME/kubespray}"
PATCH_FILE="$KUBESPRAY_DIR/roles/kubernetes-apps/cluster_roles/tasks/main.yml"

if [ ! -f "$PATCH_FILE" ]; then
  echo "File non trovato: $PATCH_FILE (il clone Kubespray potrebbe non esistere ancora)"
  exit 0
fi

# Rimuove --insecure-skip-tls-verify dalla riga kubectl apply nel task
if grep -q 'insecure-skip-tls-verify' "$PATCH_FILE"; then
  echo "Applicando patch v2.32.0: rimuovo --insecure-skip-tls-verify da $PATCH_FILE"
  sed -i 's/--insecure-skip-tls-verify //' "$PATCH_FILE"
  echo "Patch applicata."
else
  echo "Patch v2.32.0 non necessaria: il file non contiene --insecure-skip-tls-verify"
fi
