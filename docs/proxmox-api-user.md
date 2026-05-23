# Creazione automatizzata di un utente API su Proxmox con Ansible

Questo documento descrive passo‑passo come configurare, mediante Ansible, un utente che possa interagire con le API di Proxmox per creare e gestire macchine virtuali.

---

## 📋 Sommario
1. [Prerequisiti](#prerequisiti)
2. [Struttura del progetto Ansible](#struttura-del-progetto-ansible)
3. [Playbook `create_proxmox_user.yml`](#playbook-create_proxmox_useryml)
4. [Gestione sicura delle credenziali](#gestione-sicura-delle-credenziali)
5. [Esecuzione del playbook](#esecuzione-del-playbook)
6. [Utilizzo del token generato per le successive operazioni](#utilizzo-del-token-generato-per-le-successive-operazioni)
7. [Suggerimenti di sicurezza](#suggerimenti-di-sicurezza)

---

## 1️⃣ Prerequisiti <a name="prerequisiti"></a>

| Componente | Versione consigliata | Note |
|------------|---------------------|------|
| **Ansible** | `2.14+` (installabile con `pip install ansible`) | Verifica con `ansible --version`. |
| **Python** | `3.9+` | Necessario per le collection. |
| **Collection** | `community.general` | Contiene il modulo `proxmox_user`. |
| **Proxmox** | `7.x` o superiore | Le estensioni Proxmox (`pve-manager`) devono essere già installate. |
| **Certificato TLS** | Facoltativo ma consigliato | Se usi `api_validate_certs: false` il traffico è in chiaro. |

Installa la collection con:
```bash
ansible-galaxy install -r requirements.yml
```

---

## 2️⃣ Struttura del progetto Ansible <a name="struttura-del-progetto-ansible"></a>
```
root/
├── requirements.yml                # Collection da installare
├── create_proxmox_user.yml         # Playbook principale
├── group_vars/
│   └── all.yml                     # Variabili (credeziali) da cifrare con Vault
└── docs/
    └── proxmox-api-user.md         # Questa documentazione
```

* `requirements.yml` – definisce le collection necessarie.
* `create_proxmox_user.yml` – contiene tutti i task per creare l'utente, assegnare i permessi e generare il token.
* `group_vars/all.yml` – file dove inserire le password in **Ansible Vault** (vedere sotto).

---

## 3️⃣ Playbook `create_proxmox_user.yml` <a name="playbook-create_proxmox_useryml"></a>
```yaml
---
- name: "Provision Proxmox API user"
  hosts: localhost
  gather_facts: false
  vars:
    # ---- Configurazione Proxmox ----
    proxmox_host: "{{ lookup('env', 'PROXMOX_HOST') }}"
    proxmox_user: "root@pam"
    proxmox_password: "{{ vault_proxmox_root_pw }}"

    # ---- Nuovo utente API ----
    api_username: "automation"
    api_realm: "pve"
    api_password: "{{ vault_automation_user_pw }}"
    api_role: "PVEAdmin"      # oppure un ruolo più ristretto
    api_path: "/"
    api_token_id: "ansible"

  tasks:
    - name: "Create (or ensure) the API user"
      community.general.proxmox_user:
        api_user: "{{ proxmox_user }}"
        api_password: "{{ proxmox_password }}"
        api_host: "{{ proxmox_host }}"
        api_validate_certs: false         # impostare a true in produzione
        name: "{{ api_username }}@{{ api_realm }}"
        password: "{{ api_password }}"
        comment: "Automation user for Ansible VM provisioning"
        state: present

    - name: "Assign role to the user"
      uri:
        url: "https://{{ proxmox_host }}:8006/api2/json/access/acl"
        method: POST
        user: "{{ proxmox_user }}"
        password: "{{ proxmox_password }}"
        force_basic_auth: true
        validate_certs: false
        body_format: json
        body:
          path: "{{ api_path }}"
          roleid: "{{ api_role }}"
          user: "{{ api_username }}@{{ api_realm }}"
      register: acl_result
      changed_when: "200" in acl_result.status

    - name: "Create an API token for the user"
      uri:
        url: "https://{{ proxmox_host }}:8006/api2/json/access/users/{{ api_username }}@{{ api_realm }}/token/{{ api_token_id }}"
        method: POST
        user: "{{ proxmox_user }}"
        password: "{{ proxmox_password }}"
        force_basic_auth: true
        validate_certs: false
        body_format: json
        body:
          comment: "Ansible‑generated token"
      register: token_result
      changed_when: "200" in token_result.status

    - name: "Show token (store securely)"
      debug:
        msg: "Token ID: {{ api_token_id }}, Value: {{ token_result.json.data.value }}"
```

### Cosa fa il playbook
| Task | Scopo |
|------|-------|
| **Create (or ensure) the API user** | Usa il modulo `proxmox_user` per creare (o verificare) l'utente `automation@pve`. |
| **Assign role to the user** | Con una chiamata `uri` all'endpoint `/access/acl` assegna il ruolo (`PVEAdmin` di default) al percorso `/`. |
| **Create an API token for the user** | Genera un token permanente (`ansible`) che può essere usato nei successivi playbook. |
| **Show token** | Restituisce il valore del token (una tantum). Il valore deve essere salvato in un vault; non sarà più recuperabile via API. |

---

## 4️⃣ Gestione sicura delle credenziali <a name="gestione-sicura-delle-credenziali"></a>
Le password non devono mai essere in chiaro nel repository. Usa **Ansible Vault**:
```bash
# Crea o modifica la variabile cifrata
ansible-vault encrypt_string --name 'vault_proxmox_root_pw' 'LaTuaPasswordRoot'
ansible-vault encrypt_string --name 'vault_automation_user_pw' 'PasswordUtenteAPI'
```
Copia l'output (che include il blocco `!vault |`) dentro `group_vars/all.yml`.

Per eseguire il playbook con il vault:
```bash
ansible-playbook create_proxmox_user.yml --ask-vault-pass
```
Oppure specifica un file di password:
```bash
ansible-playbook create_proxmox_user.yml --vault-password-file ~/.vault_pass.txt
```

---

## 5️⃣ Esecuzione del playbook <a name="esecuzione-del-playbook"></a>
```bash
# 1. Export del nome host Proxmox (es. proxmox.local)
export PROXMOX_HOST=proxmox.mio.lan

# 2. Installa la collection (se non l'hai già fatto)
ansible-galaxy install -r requirements.yml

# 3. Esegui il playbook
ansible-playbook create_proxmox_user.yml --ask-vault-pass
```
Al termine vedrai un messaggio del tipo:
```
TASK [Show token (store securely)] *******************************************
ok: [localhost] => {
    "msg": "Token ID: ansible, Value: PVE:automation@pve!ansible=abcd1234..."
}
```
Copia il valore del token **immediatamente** e salvalo in un vault o secret manager; non potrai più recuperarlo.

---

## 6️⃣ Utilizzo del token generato per le successive operazioni <a name="utilizzo-del-token-generato-per-le-successive-operazioni"></a>
Una volta che hai il token, tutti i moduli `community.general.proxmox*` lo supportano. Esempio rapido per creare una VM:
```yaml
- name: "Create VM"
  community.general.proxmox:
    api_user: "{{ api_username }}@{{ api_realm }}!{{ api_token_id }}"
    api_token: "{{ vault_api_token_value }}"   # valore salvato in Vault
    api_host: "{{ proxmox_host }}"
    api_validate_certs: false
    vmid: 101
    name: "web01"
    cores: 2
    memory: 2048
    ostype: l26
    storage: "local-lvm"
    netif:
      net0: "virtio,bridge=vmbr0"
    state: present
```
Imposta `vault_api_token_value` nello stesso `group_vars/all.yml` (cifrato) e includi il nuovo playbook nella stessa directory.

---

## 7️⃣ Suggerimenti di sicurezza <a name="suggerimenti-di-sicurezza"></a>
* **TLS** – cambia `api_validate_certs: false` in `true` appena disponi di un certificato valido.
* **Ruolo minimo** – invece di `PVEAdmin`, crea un ruolo custom con solo i privilegi necessari (`VM.Allocate`, `VM.PowerMgmt`, `Datastore.Allocate` ecc.).
* **Rotazione token** – pianifica una rotazione periodica (es. ogni 30 gg) usando un job di Ansible o AWX.
* **Limitazione IP** – se possibile, aggiungi una regola firewall sul nodo Proxmox per consentire le chiamate API solo dall'indirizzo IP del tuo server CI.
* **Audit** – i token sono tracciabili nei log di Proxmox (`/var/log/pveproxy/access.log`). Controlla i log dopo la creazione.

---

## 📚 Ulteriori letture
* **Proxmox API Docs** – <https://pve.proxmox.com/pve-docs/api-viewer/index.html>
* **Ansible Collection `community.general`** – <https://galaxy.ansible.com/community/general>
* **Ansible Vault** – <https://docs.ansible.com/ansible/latest/user_guide/vault.html>

---

*Questo file è pensato per essere versionato insieme al resto del tuo repository Ansible. Mantienilo aggiornato se modifichi ruoli, percorsi o policy di sicurezza.*
