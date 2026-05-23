#!/usr/bin/env bash
# Genera http/user-data dall'hash della password e lancia la build Packer.
set -euo pipefail

# ── Password dell'utente ubuntu (default: "ubuntu") ──────────────────────────
UBUNTU_PASSWORD="${UBUNTU_PASSWORD:-ubuntu}"
ROOT_PASSWORD="${ROOT_PASSWORD:-packer}"

# Genera l'hash SHA-512 con openssl (disponibile su qualsiasi sistema con OpenSSL)
UBUNTU_PASSWORD_HASH=$(openssl passwd -6 "${UBUNTU_PASSWORD}")

# ── Genera http/user-data dal template ───────────────────────────────────────
mkdir -p http
sed \
  -e "s|%%UBUNTU_PASSWORD_HASH%%|${UBUNTU_PASSWORD_HASH}|g" \
  -e "s|%%ROOT_PASSWORD%%|${ROOT_PASSWORD}|g" \
  http/user-data.tpl > http/user-data

echo "[packer] http/user-data generato"

# ── Inizializza i plugin Packer ───────────────────────────────────────────────
packer init ubuntu-base.pkr.hcl

# ── Variabili obbligatorie via env ────────────────────────────────────────────
: "${PROXMOX_URL:?Imposta la variabile PROXMOX_URL}"
: "${PROXMOX_TOKEN_ID:?Imposta la variabile PROXMOX_TOKEN_ID}"
: "${PROXMOX_TOKEN_SECRET:?Imposta la variabile PROXMOX_TOKEN_SECRET}"

# ── Avvia la build ────────────────────────────────────────────────────────────
# Passa variabili opzionali tramite PACKER_ARGS, es:
#   PACKER_ARGS="-var proxmox_node=pve2" ./build.sh
packer build ${PACKER_ARGS:-} ubuntu-base.pkr.hcl
