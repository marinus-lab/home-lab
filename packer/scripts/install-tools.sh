#!/usr/bin/env bash
# Aggiornamento sistema post-autoinstall.
# I pacchetti base sono già installati dall'autoinstall (user-data/kickstart).
set -euo pipefail

if command -v apt-get &>/dev/null; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get upgrade -y -qq
    apt-get clean && rm -rf /var/lib/apt/lists/*
elif command -v dnf &>/dev/null; then
    dnf upgrade -y -q
    dnf clean all
else
    echo "Package manager non supportato" >&2
    exit 1
fi
