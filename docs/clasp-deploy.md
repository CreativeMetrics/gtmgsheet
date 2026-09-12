# Deploy di Code.gs da terminale con clasp

`clasp` è la CLI ufficiale di Google per sviluppare progetti Apps Script
localmente e inviarli (push) al progetto vero senza passare dal copia-incolla
nell'editor online. Non cambia nulla di come funziona `Code.gs` — è solo un
modo più comodo e meno rischioso di aggiornarlo, visto che ormai è un file
lungo e le modifiche a mano nell'editor web sono facili da disallineare
rispetto al repository (è già capitato in questo progetto).

Questa guida presuppone che tu abbia **già** un Google Sheet con lo script
collegato (Estensioni → Apps Script) e almeno un primo deployment Web App
attivo, seguendo il setup descritto nel [README](../README.md). `clasp` serve
da qui in poi, per gli aggiornamenti — non sostituisce il primissimo setup.

## Una tantum: installazione e login

1. **Installa Node.js** se non lo hai già (serve solo per eseguire `clasp`,
   non per lo script stesso, che resta puro Apps Script). Da
   [nodejs.org](https://nodejs.org) o col gestore pacchetti del tuo sistema.

2. **Installa clasp**:
   ```bash
   npm install -g @google/clasp
   ```

3. **Abilita la Google Apps Script API** per il tuo account — passo
   obbligatorio, senza il quale `clasp login` funziona ma ogni comando
   successivo fallisce con un errore di permessi:
   apri <https://script.google.com/home/usersettings> e attiva l'interruttore
   "Google Apps Script API". Va fatto una sola volta per account Google, non
   per progetto.

4. **Accedi**:
   ```bash
   clasp login
   ```
   Si apre il browser per l'autenticazione OAuth. **Usa lo stesso account
   Google proprietario del foglio/script** — non un altro. Le credenziali
   restano salvate nella tua home (`~/.clasprc.json`), mai dentro al
   repository.

## Una tantum per ogni foglio: collegare il repo al tuo script

`clasp` deve sapere a quale progetto Apps Script inviare il codice. Questo
va rifatto per ogni foglio diverso che usi con questo repository (ognuno ha
il proprio script, con il proprio Script ID).

1. Apri il foglio Google → Estensioni → Apps Script.
2. Icona ingranaggio (**Impostazioni del progetto**) nel menu a sinistra →
   copia il valore **ID script**.
3. Nel repository, copia il file d'esempio e incolla il tuo ID:
   ```bash
   cd apps-script
   cp .clasp.json.example .clasp.json
   ```
   Apri `.clasp.json` e sostituisci il segnaposto con l'ID copiato:
   ```json
   {
     "scriptId": "IL_TUO_SCRIPT_ID",
     "rootDir": "."
   }
   ```
   Questo file **non va mai committato** (è già escluso in `.gitignore`):
   contiene un riferimento specifico al tuo account/foglio, non al progetto
   in generale.

Non serve `clasp clone`: il codice sorgente vero vive già qui nel
repository, `clasp` deve solo saperlo *inviare*, non scaricarlo.

## Uso quotidiano: aggiornare lo script dopo una modifica

Dalla cartella `apps-script/`:

```bash
clasp push
```

Carica `Code.gs` (e `appsscript.json`, il manifest del progetto) nello
script collegato. Se ti chiede conferma perché sta per sovrascrivere il
manifest, e sei sicuro della modifica, rispondi sì (o usa `clasp push --force`
per saltare la conferma).

**Attenzione — questo aggiorna il codice "in sviluppo" (`@HEAD`), non
necessariamente l'URL `/exec` pubblico già in uso dai tag GTM.** Come nel
flusso manuale già descritto nel README, per far sì che il Web App
pubblicato rifletta il nuovo codice serve una nuova versione del
deployment. Con clasp lo fai senza aprire il browser:

```bash
clasp deployments
```

Elenca i deployment esistenti con i relativi ID (`AKfycb...`). Trova quello
di tipo "Web App" che è già collegato ai tuoi tag GTM, poi:

```bash
clasp deploy -i ID_DEL_DEPLOYMENT -d "Descrizione breve della modifica"
```

Questo crea una nuova versione e la assegna a **quello stesso** deployment:
**l'URL `/exec` resta identico**, i tag GTM non vanno toccati. È
l'equivalente da terminale di "Deploy → Gestisci deployment → Modifica →
Nuova versione" nell'editor web.

Se invece lanci `clasp deploy` **senza** `-i`, crei un deployment
completamente nuovo con un URL diverso — non è quello che vuoi per un
aggiornamento di routine, va bene solo se stai deliberatamente creando un
secondo Web App separato.

## Riepilogo dei comandi

| Comando | Cosa fa |
|---|---|
| `clasp login` | Autentica il tuo account Google (una tantum) |
| `clasp push` | Invia `Code.gs`/`appsscript.json` locali allo script (aggiorna `@HEAD`) |
| `clasp open` | Apre l'editor Apps Script del progetto collegato nel browser |
| `clasp deployments` | Elenca i deployment esistenti e i loro ID |
| `clasp deploy -i ID -d "nota"` | Pubblica una nuova versione su un deployment esistente (stesso URL `/exec`) |
| `clasp deploy` (senza `-i`) | Crea un **nuovo** deployment con un **nuovo** URL — di norma non è quello che vuoi |

## Cosa NON cambia

- Il token e l'URL Web App restano dove sono sempre stati: in
  `PropertiesService`, gestiti dal menu **Sheets Logger (GTM)** nel foglio.
  `clasp push` aggiorna il codice, non tocca queste proprietà.
- I template `.tpl` in `web-client-tag/` e `server-side-tag/` restano
  template GTM da importare in GTM normalmente — clasp riguarda solo
  `apps-script/Code.gs`.
- Se preferisci continuare a copiare `Code.gs` a mano nell'editor web,
  resta un'opzione perfettamente valida: clasp è comodo, non obbligatorio.
