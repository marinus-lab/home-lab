# init-project.sh — Inizializzazione automatica del progetto

## Panoramica

`init-project.sh` è uno script interattivo che automatizza tutta la configurazione iniziale del progetto. Eseguito una sola volta, prepara:

- Credenziali Proxmox cifrate con Ansible Vault
- Utente API automation su Proxmox (personalizzabile)
- Token API per Packer e Terraform
- File di configurazione pronti (`packer.pkrvars.hcl`, `terraform.tfvars`)

Dopo il suo completamento, **tutta la pipeline è automatica** — niente più input manuale di credenziali.

---

## Prerequisiti

| Prerequisito | Come verificare | Come ottenere |
|--------------|-----------------|---------------|
| Bash | `bash --version` | Incluso in Linux/macOS |
| Ansible | `ansible --version` | Installato da `setup-bastion.sh` |
| Accesso root Proxmox | `ssh root@<IP_PROXMOX>` | Configurazione Proxmox standard |
| IP Proxmox noto | Scritto da qualche parte | Controllare l'interfaccia Proxmox |

---

## Esecuzione

```bash
cd ~/home-lab
bash init-project.sh
```

Lo script è **interattivo** — pone domande in sequenza. Non è necessario aggiungere argomenti da linea di comando.

---

## Input richiesti

### 1. IP/hostname Proxmox

```
IP/hostname Proxmox (es. 192.168.1.10):
```

Inserisci l'indirizzo IP della macchina Proxmox. Esempi validi:
- `192.168.1.10`
- `proxmox.homelab.local`
- `pve.mio.lan`

### 2. Password root Proxmox

```
Password utente root@pam di Proxmox:
```

La password dell'utente `root` su Proxmox (non verrà visualizzata mentre digiti). Lo script la usa per:
- Autenticarsi all'API Proxmox
- Creare l'utente `automation`
- Generare il token API

**⚠️ Nota:** questa password viene cifrata in `group_vars/all.yml` con Ansible Vault e non rimane in chiaro.

### 3. Nome utente automation (personalizzabile)

```
Nome utente automation (default: automation):
```

Scegli il nome dell'utente che verrà creato su Proxmox per le operazioni automatiche. Esempi:
- `automation` (default)
- `terraform-user`
- `packer-bot`
- `homelab-ops`

Lasciar vuoto usa il default `automation`. Il nome può contenere solo caratteri alfanumerici e underscore.

### 4. Password utente automation

```
Password per utente <nome_scelto>:
```

Una password per il nuovo utente automation che verrà creato su Proxmox. Scegline una sicura (almeno 12 caratteri). Questa password:
- Non verrà usata per login manuali (il token API è quello che conta)
- Viene cifrata in Vault insieme alle altre credenziali

### 5. Password Vault

```
Password per il Vault (proteggere bene!):
```

Una password **per proteggere** tutte le credenziali Proxmox cifrate. Questa password:
- **Non deve essere dimenticata** — è l'unica che permette di decifrare i segreti
- Viene salvata in `~/.vault_pass` sul bastion
- Deve essere **lunga e complessa** (almeno 16 caratteri)

**⚠️ Importante:** questa password è come la master key — proteggi il file `~/.vault_pass`!

---

## Flusso di esecuzione

Dopo aver inserito tutti gli input, lo script:

```
1. Verifica i prerequisiti (ansible, ansible-vault presenti)
   ↓
2. Salva la password Vault in ~/.vault_pass (chmod 600)
   ↓
3. Cifra le credenziali Proxmox in group_vars/all.yml
   ├── vault_proxmox_root_pw
   └── vault_automation_user_pw
   ↓
4. Genera packer/packer.pkrvars.hcl (versione preliminare)
   ↓
5. Genera terraform/terraform.tfvars (versione preliminare)
   ↓
6. Installa collezioni Ansible (community.proxmox)
   ↓
7. Esegue create_proxmox_user.yml
   ├── Crea utente <nome_scelto>@pve su Proxmox
   ├── Assegna ruolo PVEAdmin
   └── Genera token API
   ↓
8. Estrae il token dal log di Ansible
   ↓
9. Aggiorna packer/packer.pkrvars.hcl con il token
   ↓
10. Aggiorna terraform/terraform.tfvars con il token
   ↓
11. Mostra riepilogo con i prossimi passi
```

---

## Output dello script

### File creati/modificati

| File | Contenuto | Gitignore? |
|------|-----------|-----------|
| `group_vars/all.yml` | Credenziali cifrate con Vault | ❌ Tracciato |
| `packer/packer.pkrvars.hcl` | Token API e IP Proxmox | ✅ Ignorato |
| `terraform/terraform.tfvars` | Token API e parametri cluster | ✅ Ignorato |
| `~/.vault_pass` | Password Vault (sul bastion) | — |

### Console output

Lo script mostra un riepilogo finale:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ✅ INIZIALIZZAZIONE COMPLETATA
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

File creati/aggiornati:
  • group_vars/all.yml                    (credenziali cifrate)
  • packer/packer.pkrvars.hcl             (configurazione Packer)
  • terraform/terraform.tfvars            (configurazione Terraform)

Credenziali Vault salvate in:
  • /root/.vault_pass                   (proteggere!)

Prossimi passi:
  1. cd packer && ./build.sh              (crea template VM)
  2. cd ../terraform && terraform apply   (crea VM K8s)
  3. cd ../kubespray && ./deploy.sh       (installa Kubernetes)

Per decifrare le credenziali:
  ansible-vault view group_vars/all.yml --vault-password-file ~/.vault_pass
```

---

## Cosa succede dietro le quinte

### Ansible Vault

Lo script cifra le credenziali usando `ansible-vault`:

```bash
# Leggi come fa il script
ansible-vault encrypt_string --vault-password-file ~/.vault_pass \
  --name vault_proxmox_root_pw \
  "<password>"
```

Il risultato nel file `group_vars/all.yml`:

```yaml
---
vault_proxmox_root_pw: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  66386d8c2e8d8c8d8c8d8c8d8c8d8c8d8c8d8c8d8c8d8c8d8c8d8c8d8c8d8c8d
  8c8d8c8d8c8d8c8d8c8d8c8d8c8d8c8d
  ...
```

Solo chi ha la password Vault (`~/.vault_pass`) può decifrare il contenuto.

### Creazione utente Proxmox

Lo script esegue il playbook `create_proxmox_user.yml` che:

1. Si autentica come `root@pam` su Proxmox
2. Crea l'utente `<nome_scelto>@pve`
3. Assegna il ruolo `PVEAdmin`
4. Genera un token API permanente

Il token ha formato: `<nome_scelto>@pve!<tokenid>=<secret_uuid>`

### Token per Packer e Terraform

Lo script crea **un unico token** e lo usa per entrambi:
- Packer: `<nome_scelto>@pve!packer=<secret_uuid>`
- Terraform: `<nome_scelto>@pve!terraform=<secret_uuid>`

Se preferisci separare, modifica manualmente in `create_proxmox_user.yml` la variabile `api_token_id`.

---

## Dopo init-project.sh

Una volta completato lo script, **tutti i file sono pronti**. Le operazioni successive non chiedono più credenziali:

### Packer

```bash
cd packer
./build.sh  # Legge automaticamente da packer.pkrvars.hcl
```

### Terraform

```bash
cd terraform
terraform apply  # Legge automaticamente da terraform.tfvars
```

### Kubespray

```bash
cd kubespray
./deploy.sh  # Legge automaticamente da inventory e group_vars
```

---

## Sicurezza

### Cosa è cifrato

- ✅ Password root Proxmox
- ✅ Password utente automation
- ❌ Token API (salvato in chiaro in `.tfvars` e `.pkrvars.hcl`)

### Proteggere ~/.vault_pass

La password Vault è salvata in `~/.vault_pass` con permessi `600` (solo lettura per l'utente):

```bash
# Verifica i permessi
ls -la ~/.vault_pass
# -rw------- 1 user user ... ~/.vault_pass

# Non condividere questo file!
```

Se qualcuno accede a questo file, può decifrare tutte le credenziali.

### Se perdi ~/.vault_pass

Non potrai più decifrare `group_vars/all.yml`. Opzioni:

1. **Ricreare tutto:**
   ```bash
   rm group_vars/all.yml ~/.vault_pass
   bash init-project.sh  # esegui di nuovo
   ```

2. **Recuperare la password da backup:**
   Se l'hai salvata da qualche parte, incollala di nuovo in `~/.vault_pass`

---

## Troubleshooting

### "ansible not found"

Lo script richiede `setup-bastion.sh` già eseguito. Eseguilo prima:

```bash
bash setup-bastion.sh
```

### "Proxmox API connection failed"

L'IP o la password Proxmox è sbagliato. Verifica:

```bash
# Test di connessione
ssh root@<IP_PROXMOX> "echo OK"
```

### "Token not generated"

Il playbook `create_proxmox_user.yml` è fallito. Controlla il log di Ansible:

```bash
ansible-playbook create_proxmox_user.yml \
  --vault-password-file ~/.vault_pass \
  -e "proxmox_host=<IP>"  # fornisci di nuovo l'IP
```

### Non riesco a decifrare group_vars/all.yml

```bash
# Verifica che ~/.vault_pass esista e contenga la password giusta
cat ~/.vault_pass

# Prova a decifrare
ansible-vault view group_vars/all.yml --vault-password-file ~/.vault_pass
```

---

## Casi d'uso avanzati

### Cambiare il nome utente automation

Se vuoi usare un nome diverso da quello che hai scelto:

1. Modifica `create_proxmox_user.yml` variabile `api_username`
2. Riesegui lo script
3. Cancella il vecchio utente da Proxmox manualmente

### Rigenerare il token

Se il token è compromesso:

```bash
# Da Proxmox (via console o SSH)
pveum token remove <username>@pve!<tokenid>
pveum token add <username>@pve <tokenid>

# Aggiorna i file .tfvars e .pkrvars.hcl manualmente
```

### Usare credenziali già esistenti

Se hai già un utente Proxmox con token, salta `init-project.sh` e:

1. Crea manualmente `packer/packer.pkrvars.hcl`
2. Crea manualmente `terraform/terraform.tfvars`
3. Crea manualmente `group_vars/all.yml` con Vault

---

## Flusso completo dall'inizio

```bash
# 1. Clone il repo e naviga
git clone https://github.com/marinus-lab/home-lab.git
cd home-lab

# 2. Setup bastion
bash setup-bastion.sh

# 3. Inizializza progetto (una sola volta!)
bash init-project.sh
# → Inserisci IP Proxmox, password root, nome utente, password Vault

# 4. Ora tutto è automatico
cd packer && ./build.sh
cd ../terraform && terraform apply
cd ../kubespray && ./deploy.sh

# 5. Cluster pronto
kubectl get nodes
```
