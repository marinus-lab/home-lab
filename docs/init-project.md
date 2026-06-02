# init-project.sh — Inizializzazione automatica del progetto

## Panoramica

`init-project.sh` è uno script interattivo che automatizza tutta la configurazione iniziale del progetto. Prepara:

- Credenziali Proxmox cifrate con Ansible Vault
- Utente API automation su Proxmox (personalizzabile)
- Token API per Packer e Terraform
- File di configurazione pronti (`packer.pkrvars.hcl`, `terraform.tfvars`)

Dopo il suo completamento, **tutta la pipeline è automatica** — niente più input manuale di credenziali.

**⚠️ Idempotente:** Lo script può essere eseguito **più volte** in sicurezza. Se utente o token già esistono, vengono rigenerati automaticamente (non fallisce).

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

**Validazione:** Tutti gli input vengono validati. Se un input non è accettato, lo script chiede di nuovo finché non inserisci un valore valido. Non puoi saltare nessun campo.

Le domande sono organizzate per sezioni con **linee vuote di separazione** per maggiore leggibilità:

```
🔌 CREDENZIALI PROXMOX
[IP, password root]

👤 UTENTE AUTOMATION
[nome utente]

🔐 PASSWORD UTENTE AUTOMATION
[password]

🌐 RETE KUBERNETES
[subnet, gateway, IP master, IP worker]

🔐 PASSWORD VAULT
[password]

💾 RILEVAMENTO STORAGE PROXMOX  (dopo connessione API)
[selezione storage ISO e template da lista dinamica]
```

### Verifica il risultato

Dopo l'esecuzione, verifica che tutto è stato configurato correttamente:

```bash
bash verify-init.sh
```

Lo script controlla:
- ✅ File di configurazione `packer/packer.pkrvars.hcl` (token, iso_storage_pool, template_storage_pool)
- ✅ File di configurazione `terraform/terraform.auto.tfvars` (token, credenziali, rete K8s, storage)
- ✅ Parametri rete K8s presenti (k8s_subnet, k8s_gateway, master_ip_start, worker_ip_start)
- ✅ Storage pool senza PLACEHOLDER residui
- ✅ Password Vault salvata con permessi corretti
- ✅ Credenziali cifrate presenti nel Vault
- ✅ Connessione API Proxmox funzionante
- ✅ Token API valido e funzionante
- ✅ Nodo Proxmox rilevato e valido
- ✅ **Storage Proxmox esistono realmente** (verifica via API che gli storage selezionati siano disponibili sul nodo)
- ✅ Dipendenze (curl, ansible-vault, terraform, packer, python3) disponibili

**Nota importante:** `verify-init.sh` controlla il token in `terraform.auto.tfvars` (file privato con credenziali), **non** in `terraform.tfvars` (file pubblico con solo configurazione).

Se tutto passa, sei pronto per procedere con Packer/Terraform/Kubespray! ✅

---

## Validazione input

Lo script **controlla tutti gli input** e continua a chiedere finché non inserisci un valore valido:

| Input | Validazione | Azione se invalido |
|-------|-------------|-------------------|
| IP/hostname Proxmox | Non vuoto | Chiede di nuovo |
| Password root Proxmox | Non vuota | Chiede di nuovo |
| Nome utente automation | Ha default `automation` | Non richiesto se vuoto |
| Password utente automation | Min 8 caratteri | Chiede di nuovo |
| Subnet Kubernetes | Formato CIDR valido (X.X.X.X/XX) | Chiede di nuovo |
| Gateway Kubernetes | Formato IP valido (X.X.X.X) | Chiede di nuovo |
| Master IP ottetto | Numero 0-253 | Chiede di nuovo |
| Worker IP ottetto | Numero 0-253 + > Master+2 | Chiede di nuovo |
| Password Vault | Non vuota | Chiede di nuovo |
| Storage ISO | Numero in range (1-N opzioni rilevate da Proxmox) | Chiede di nuovo |
| Storage template | Numero in range (1-N opzioni rilevate da Proxmox) | Chiede di nuovo |

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

**Validazione:** Non può essere vuoto.

### 2. Password root Proxmox

```
Password utente root@pam di Proxmox:
```

La password dell'utente `root` su Proxmox (non verrà visualizzata mentre digiti). Lo script la usa per:
- Autenticarsi all'API Proxmox
- Creare l'utente `automation`
- Generare il token API

**Validazione:** Non può essere vuota.

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

**Validazione:** Se lasciato vuoto, usa il default `automation`. Il nome dovrebbe contenere solo caratteri alfanumerici e underscore.

### 4. Password utente automation

```
Password per utente <nome_scelto> (min 8 caratteri):
```

Una password per il nuovo utente automation che verrà creato su Proxmox. Deve avere **almeno 8 caratteri** (vincolo Proxmox). Scegline una complessa e lunga. Questa password:
- Non verrà usata per login manuali (il token API è quello che conta)
- Viene cifrata in Vault insieme alle altre credenziali

**Validazione:** Minimo 8 caratteri obbligatorio. Se troppo corta, lo script chiede di nuovo.

### 5. Subnet Kubernetes

```
Subnet Kubernetes (es. 192.168.0.0/24):
```

La subnet dove verranno posizionate le VM del cluster Kubernetes. Esempi validi:
- `192.168.0.0/24` (ipotesi default, stesso range di MetalLB)
- `10.0.0.0/24`
- `172.16.0.0/24`

Questa subnet deve essere raggiungibile dalla macchina dove esegui Terraform.

**Validazione:** Deve essere in formato CIDR valido (`X.X.X.X/XX`). Se il formato non è corretto, lo script chiede di nuovo.

### 6. Gateway Kubernetes

```
Gateway Kubernetes (es. 192.168.0.1):
```

L'indirizzo IP del gateway per la subnet Kubernetes. Di solito è il primo indirizzo disponibile (`.1`) oppure il router della tua rete.

**Validazione:** Deve essere in formato IP valido (`X.X.X.X`). Se il formato non è corretto, lo script chiede di nuovo.

### 7. Ultimo ottetto IP primo master

```
Ultimo ottetto IP primo master (es. 210):
```

Gli IP dei 3 master verranno calcolati automaticamente incrementando questo valore:
- Master 1: `<subnet>.210`
- Master 2: `<subnet>.211`
- Master 3: `<subnet>.212`

Scegli un valore che non crei conflitti con altri host nella subnet.

**Validazione:** Deve essere un numero tra 0 e 253. Se non valido, lo script chiede di nuovo.

### 8. Ultimo ottetto IP primo worker

```
Ultimo ottetto IP primo worker (es. 220):
```

Gli IP dei 3 worker verranno calcolati automaticamente incrementando questo valore:
- Worker 1: `<subnet>.220`
- Worker 2: `<subnet>.221`
- Worker 3: `<subnet>.222`

Scegli un valore superiore al range dei master per evitare conflitti.

**Validazione:** Deve essere un numero tra 0 e 253, e **deve essere maggiore di `Master IP + 2`** per evitare sovrapposizioni. Se non valido, lo script chiede di nuovo.

### 9. Password Vault

```
Password per il Vault (proteggere bene!):
```

Una password **per proteggere** tutte le credenziali Proxmox cifrate. Questa password:
- **Non deve essere dimenticata** — è l'unica che permette di decifrare i segreti
- Viene salvata in `~/.vault_pass` sul bastion
- Deve essere **lunga e complessa** (almeno 16 caratteri)

**Validazione:** Non può essere vuota. Lo script chiede di nuovo finché non la inserisci.

**⚠️ Importante:** questa password è come la master key — proteggi il file `~/.vault_pass`!

---

## Flusso di esecuzione

Dopo aver inserito tutti gli input, lo script:

```
1. Verifica i prerequisiti (curl, ansible-vault, python3 presenti)
   ↓
2. Salva la password Vault in ~/.vault_pass (chmod 600)
   ↓
3. Cifra le credenziali Proxmox in group_vars/all.yml
   ├── vault_proxmox_root_pw (cifrata)
   └── vault_automation_user_pw (cifrata)
   ↓
4. Genera packer/packer.pkrvars.hcl con placeholder
   ├── Token (placeholder)
   ├── Nodo (placeholder)
   ├── Storage ISO (placeholder)
   └── Storage template (placeholder)
   ↓
5. Genera terraform/terraform.auto.tfvars con placeholder + rete + storage
   ↓
6. Ottiene ticket di sessione Proxmox (API ticket-based auth)
   ↓
7. Rileva nodo Proxmox disponibile via API
   ├── Se un solo nodo: lo seleziona automaticamente
   └── Se più nodi: chiede all'utente di scegliere
   ↓
8. 💾 Rileva storage Proxmox via API /nodes/<node>/storage
   ├── Filtra storage abilitati (enabled=1, active=1)
   ├── Mostra lista storage con tipo e content
   ├── Chiede selezione storage per ISO (content include "iso")
   └── Chiede selezione storage per template (content include "images")
   ↓
9. Crea/verifica utente <nome_scelto>@pve su Proxmox (con curl)
   ↓
10. Crea token packer (o lo rigenera se già esiste)
    ├── Se token esiste: lo elimina e ricrea
    └── Estrae il secret dal JSON di risposta
   ↓
11. Crea token terraform (o lo rigenera se già esiste)
    ├── Se token esiste: lo elimina e ricrea
    └── Estrae il secret dal JSON di risposta
    ↓
12. Aggiorna packer/packer.pkrvars.hcl con valori reali
    ├── Token, nodo
    └── iso_storage_pool, template_storage_pool
    ↓
13. Aggiorna terraform/terraform.auto.tfvars con valori reali
    ├── Token, nodo, rete
    └── storage_pool
    ↓
14. Mostra riepilogo con i prossimi passi
```

---

## Output dello script

### File creati/modificati

| File | Contenuto | Tracciato? |
|------|-----------|-----------|
| `group_vars/all.yml` | Credenziali Proxmox cifrate con Vault | ✅ Sì |
| `packer/packer.pkrvars.hcl` | Token Packer + IP Proxmox | ❌ .gitignore |
| `terraform/terraform.tfvars` | Topologia cluster (3M+3W, risorse, SSH key path) | ❌ .gitignore |
| `terraform/terraform.auto.tfvars` | Credenziali Proxmox + configurazione rete | ❌ .gitignore |
| `terraform/terraform.auto.tfvars.example` | Template credenziali + rete | ✅ Sì |
| `~/.vault_pass` | Password Vault (sul bastion) | — |

### Console output

Lo script mostra un riepilogo finale:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ✅ INIZIALIZZAZIONE COMPLETATA
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

File creati/aggiornati:
  • group_vars/all.yml                    (credenziali Proxmox cifrate)
  • packer/packer.pkrvars.hcl             (token Packer - privato)
  • terraform/terraform.auto.tfvars       (credenziali Terraform - privato)
  • terraform/terraform.tfvars            (configurazione cluster - pubblico)

Credenziali Vault salvate in:
  • /root/.vault_pass                   (proteggere!)

Prossimi passi:
  1. cd packer && ./build.sh              (crea template VM)
   2. cd ../terraform && terraform init && terraform apply -parallelism=2   (crea VM K8s)
  3. cd ../kubespray && ./deploy.sh       (installa Kubernetes)

Per decifrare le credenziali:
  ansible-vault view group_vars/all.yml --vault-password-file ~/.vault_pass
```

---

## Cosa succede dietro le quinte

### Ansible Vault

Lo script cifra le credenziali usando `ansible-vault encrypt_string`:

```bash
# Per ogni variabile, lo script cattura l'output di encrypt_string
echo "password" | ansible-vault encrypt_string --vault-password-file ~/.vault_pass
```

Il risultato nel file `group_vars/all.yml` è YAML con variabili individuali cifrate:

```yaml
---
vault_proxmox_root_pw: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  66386d8c2e8d8c8d8c8d8c8d8c8d8c8d8c8d8c8d8c8d8c8d8c8d8c8d8c8d8c8d
  8c8d8c8d8c8d8c8d8c8d8c8d8c8d8c8d
vault_automation_user_pw: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  37646166363165653832636434613032336337626136653330346666333536383037...
```

Solo chi ha la password Vault (`~/.vault_pass`) può decifrare il contenuto. Per visualizzare:

```bash
ansible-vault view group_vars/all.yml --vault-password-file ~/.vault_pass
```

### Autenticazione Proxmox

Lo script usa **ticket-based authentication** (metodo standard di Proxmox):

1. **Ottiene il ticket**: POST a `/api2/json/access/ticket` con root@pam credentials
2. **Usa il ticket**: Invia PVEAuthCookie (ticket) e CSRFPreventionToken header per operazioni API
3. **Crea utente e token**: Con curl, non Ansible

### Rilevamento storage dinamico

Lo script **rileva automaticamente gli storage disponibili** su Proxmox via API:

1. **Chiama** `GET /api2/json/nodes/<node>/storage` per ottenere la lista completa
2. **Filtra** storage abilitati (`enabled=1`, `active=1`)
3. **Filtra per ISO**: mostra solo storage con `content` che include `iso`
4. **Filtra per template**: mostra solo storage con `content` che include `images`
5. **Chiede selezione** all'utente tramite menu numerato

Esempio di output:
```
📀 Storage disponibili per ISO (download installer):

  1) local           [tipo: dir        content: iso,vztmpl,backup]
  2) nfs-iso         [tipo: nfs        content: iso]

Seleziona storage per ISO (1-2):

💿 Storage disponibili per VM disk (template):

  1) local-lvm       [tipo: lvmthin    content: images,rootdir]
  2) ceph-pool       [tipo: rbd        content: images]

Seleziona storage per template VM (1-2):
```

Questo evita di hardcodare valori che variano da setup a setup.

### Token API Proxmox

Lo script crea **due token separati**:
- Packer: `<nome_scelto>@pve!packer=<secret_uuid>`
- Terraform: `<nome_scelto>@pve!terraform=<secret_uuid>`

Se un token esiste già (da una precedente esecuzione), viene **eliminato e ricreato** automaticamente con un nuovo secret.

### Idempotenza

Se esegui lo script di nuovo:
- ✅ Utente esiste? → Continua (non fallisce)
- ✅ Token esiste? → Lo elimina e ricrea con nuovo secret
- ✅ File di config esistono? → Sovrascritti con nuovi valori
- ✅ Vault già creato? → Mantiene gli stessi dati

### Terraform: separazione credenziali e configurazione

Per motivi di sicurezza e condivisione del codice, i file Terraform sono separati:

**`terraform/terraform.tfvars`** (pubblico - NON tracciato in git, ma condivisibile via esempio)
```hcl
# Configurazione cluster
control_plane_count = 3
worker_count        = 3
master_memory       = 16384
# ... configurazione personalizzabile e versionata
```

**`terraform/terraform.auto.tfvars`** (privato - in .gitignore)
```hcl
# Credenziali Proxmox (generate da init-project.sh)
proxmox_url          = "..."
proxmox_token_id     = "..."
proxmox_token_secret = "..."
```

Terraform carica automaticamente i file `*.auto.tfvars` dopo `*.tfvars`, quindi:
- ✅ Configurazione cluster è versionata e condivisibile
- ✅ Credenziali rimangono private (mai in git)
- ✅ Team members usano lo stesso `terraform.tfvars` con loro credenziali

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
terraform init
terraform apply -parallelism=2  # Legge automaticamente da terraform.tfvars
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

Il playbook `ansible/playbooks/create_proxmox_user.yml` è fallito. Controlla il log di Ansible:

```bash
ansible-playbook ansible/playbooks/create_proxmox_user.yml \
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

1. Modifica `ansible/playbooks/create_proxmox_user.yml` variabile `api_username`
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
cd ../terraform && terraform init && terraform apply -parallelism=2
cd ../kubespray && ./deploy.sh

# 5. Cluster pronto
kubectl get nodes
```
