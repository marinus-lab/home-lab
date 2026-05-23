# Generato automaticamente da init-project.sh

# ── Credenziali Proxmox ────────────────────────────────────────────────────────
proxmox_url          = "https://192.168.0.93:8006/api2/json"
proxmox_token_id     = "gaute@pve!packer"
proxmox_token_secret = "4bf745f2-4a10-47d3-ba35-c2bcd1418a8c"
proxmox_node         = "PLACEHOLDER_NODO"

# ── Storage Packer (rilevati dinamicamente da Proxmox API) ────────────────────
iso_storage_pool      = "Diskstation"
template_storage_pool = "RAID6TB"
