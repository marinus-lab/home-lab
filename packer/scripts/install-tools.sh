#!/usr/bin/env bash
# Aggiornamento sistema post-autoinstall.
# I pacchetti base sono già installati dall'autoinstall (user-data.tpl).
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get upgrade -y -qq
apt-get clean && rm -rf /var/lib/apt/lists/*
