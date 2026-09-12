# GTM → Google Sheets

Due template GTM che scrivono dati (eventi, form, log) in un Google Sheet
chiamando lo **stesso** Apps Script Web App — uno dal browser, l'altro dal
container server:

| Template | Container | File | Come autentica |
|---|---|---|---|
| **Google Sheets Logger** | Web (client-side) | [`web-client-tag/google-sheets-logger.tpl`](web-client-tag/google-sheets-logger.tpl) | Nessuna — chiama in GET (`sendPixel`) l'Apps Script Web App pubblico |
| **Google Sheets Writer** | Server-side | [`server-side-tag/google-sheets-writer.tpl`](server-side-tag/google-sheets-writer.tpl) | Nessuna — chiama in POST (`sendHttpRequest`) lo stesso Apps Script Web App |

Nessuno dei due usa le Google API o un service account: l'unica cosa da
pubblicare è l'Apps Script in [`apps-script/Code.gs`](apps-script/Code.gs).
Entrambi si importano in GTM da **Templates → New → menu ⋮ → Import**
(Template Gallery interna al container, non la Community Gallery pubblica),
selezionando il relativo file `.tpl`.

## Quale usare

- Hai un container **server-side**? Usa `google-sheets-writer.tpl`: stesso
  Apps Script del tag client, ma chiamato in POST da server a server. Non
  espone mai l'URL né il token al browser, e legge davvero lo status della
  risposta (a differenza di `sendPixel`, che non può).
- Ti serve loggare qualcosa che esiste **solo nel browser** e non arriva
  mai al server (es. un errore JS, un'interazione UI che non generi come
  evento verso sGTM), oppure non hai un container server-side: usa
  `google-sheets-logger.tpl`.

Sono complementari, non alternativi: puoi tenerli entrambi nello stesso
progetto, anche puntati allo stesso foglio/deployment.

## Struttura del repository

```
web-client-tag/
  google-sheets-logger.tpl   ← template GTM da importare nel container Web
server-side-tag/
  google-sheets-writer.tpl   ← template GTM da importare nel container Server
apps-script/
  Code.gs                    ← script da incollare nel foglio (usato da entrambi i tag)
  appsscript.json            ← manifest del progetto Apps Script (usato da clasp)
  .clasp.json.example        ← copialo in .clasp.json e inserisci il tuo Script ID
docs/
  no-apps-script-alternatives.md
  clasp-deploy.md            ← deploy di Code.gs da terminale, senza copia-incolla
scripts/
  verify-templates.js        ← controlli di coerenza usati dalla CI (vedi sotto)
.github/workflows/
  verify-templates.yml       ← esegue verify-templates.js ad ogni push/PR
```

## Setup — Apps Script (comune a entrambi i tag)

Il primo setup si fa nell'editor web (sotto). Per gli aggiornamenti
successivi a `Code.gs`, [`docs/clasp-deploy.md`](docs/clasp-deploy.md)
spiega come inviarli da terminale con `clasp` invece di copiarli a mano —
utile perché il file è cresciuto ed è facile disallinearlo dall'editor
web modificandolo solo lì. Resta comunque possibile continuare a
copia-incollare come descritto qui sotto, se preferisci.

1. Apri il Google Sheet di destinazione → Estensioni → Apps Script.
2. Incolla il contenuto di `apps-script/Code.gs` (nessuna costante da
   modificare: token e URL si gestiscono dal menu, vedi sotto).
3. Deploy → Nuovo deployment → App web → Esegui come "Me" → Accesso
   "Chiunque". Copia l'URL `/exec` mostrato a fine deploy.
4. Ricarica la pagina del foglio: comparirà il menu **Sheets Logger
   (GTM)**.
   - **Imposta URL Web App** → incolla l'URL copiato al punto 3. **Non
     usare un URL rilevato in automatico**: `ScriptApp.getService().getUrl()`,
     su account Google Workspace, può restituire un URL nel formato
     `.../a/TUODOMINIO/macros/s/.../exec` con un **deployment ID diverso**
     da quello reale — un URL che sembra valido (contiene `/exec`) ma
     punta a un deployment sbagliato. L'unico URL affidabile è quello
     copiato dalla schermata Deploy → Gestisci deployment.
   - **Mostra configurazione** → un unico popup con i tre valori pronti
     da incollare nei tag: **URL del Web App** (quello appena impostato;
     se non l'hai ancora fatto, il popup può mostrare comunque un valore
     "intercettato automaticamente" a puro scopo diagnostico, etichettato
     come non verificato), **nome del foglio (tab)** attivo (con l'elenco
     degli altri fogli, se il file ne ha più di uno) e **token condiviso**
     (generato al primo utilizzo, mai da inventare a mano).

Il codice è duplicato anche nella sezione Documentazione di
`google-sheets-logger.tpl` (`___NOTES___`), così resta visibile
direttamente dall'interfaccia GTM a chi importa il template senza dover
aprire il repository.

## Setup rapido — tag client-side

1. Completa il setup Apps Script sopra.
2. In GTM (container Web): importa `web-client-tag/google-sheets-logger.tpl`,
   crea il tag, incolla i tre valori mostrati da "Mostra configurazione"
   (URL, nome del foglio, token) nei rispettivi campi, compila la tabella
   colonna→valore, assegna un trigger.
3. Verifica in preview (tab della richiesta in uscita) e controlla che la
   riga compaia nel foglio.

## Setup rapido — tag server-side

1. Completa lo stesso setup Apps Script sopra (può essere lo stesso
   deployment usato dal tag client, o uno diverso — in tal caso avrà un
   suo URL/token separati).
2. In GTM (container Server): importa
   `server-side-tag/google-sheets-writer.tpl`, crea il tag, incolla gli
   stessi tre valori di "Mostra configurazione" usati per il tag client,
   compila la tabella colonna→valore mappando variabili di event data
   (es. `{{Event Name}}`, `{{Client ID}}`), assegna un trigger.
3. Verifica in preview lo status code e il body della risposta
   (`{"ok":true}` = riga scritta) verso `script.google.com` /
   `script.googleusercontent.com`.

## Il token si genera da solo, ma resta un bearer token

`Code.gs` non ha più una costante `SHARED_SECRET` da editare: il token è
generato con `Utilities.getUuid()` al primo utilizzo (o quando lo
rigeneri dal menu) e vive in `PropertiesService`, non nel codice — quindi
non finisce mai per errore in un export del container o in un file
condiviso. Resta comunque un valore statico che chi lo ottiene può
riusare finché non lo rigeneri: non è "autenticazione" in senso stretto.
Sul tag client-side in particolare, il token stesso viaggia comunque nel
JavaScript eseguito nel browser (nessun modo di evitarlo in quel sandbox);
sul tag server-side invece non lascia mai il container. Alternative
valutate (firma HMAC con timestamp, allowlist IP) e perché non risolvono
il problema alla radice in un contesto client-side sono descritte nella
sezione "Il token: come viene generato e alternative" di
`web-client-tag/google-sheets-logger.tpl`.

Dettagli completi nella sezione Documentazione di ciascun template
(`___NOTES___` nel rispettivo file `.tpl`).

## "Posso evitare del tutto Apps Script?"

In questo repository, no: entrambi i tag dipendono dallo stesso Apps
Script, per scelta — niente Google Cloud, niente Sheets API, niente
service account da configurare. Se in futuro preferisci eliminare anche
l'Apps Script, la via è far chiamare al tag server-side direttamente la
Google Sheets API v4 con `getGoogleAuth` (Application Default Credentials
del container, disponibile solo se il container gira su Google Cloud):
il dettaglio di come farlo resta documentato in
[`docs/no-apps-script-alternatives.md`](docs/no-apps-script-alternatives.md)
insieme ad altre opzioni (trucco Google Form, servizi terzi come Sheety/
SheetDB), per riferimento se dovesse servire.

## Test automatizzati dei template

Entrambi i `.tpl` hanno scenari di test nel tab **Tests** dell'editor GTM
(sezione `___TESTS___`), eseguibili con il pulsante "Run tests" quando
apri/modifichi il template in GTM. Coprono: costruzione corretta della
richiesta (URL/query string per il client, body JSON per il server),
gestione di successo/fallimento, e le protezioni descritte sopra (nomi di
colonna riservati, colonne duplicate, chiave di deduplicazione) — pensati
per restare verdi finché il comportamento documentato non cambia
deliberatamente, così una modifica futura che lo rompesse per errore
verrebbe segnalata subito.

## CI — verifica automatica ad ogni push

`.github/workflows/verify-templates.yml` esegue `scripts/verify-templates.js`
ad ogni push e pull request. Controlla, senza bisogno di aprire GTM o
Apps Script:

- che la sintassi JavaScript di `apps-script/Code.gs` e delle sezioni
  sandboxed di entrambi i `.tpl` sia valida;
- che la copia di `Code.gs` incorporata in `___NOTES___` di
  `web-client-tag/google-sheets-logger.tpl` sia **byte-identica** (riga
  per riga) al file reale — segnalando la prima riga diversa, se non lo è;
- che i blocchi ` ``` ` nei `.tpl` siano bilanciati (nessuna fence
  markdown aperta e mai chiusa);
- che tutte le sezioni `___..._ ___` obbligatorie siano presenti in
  entrambi i file;
- che `___INFO___`, `___TEMPLATE_PARAMETERS___` e
  `___WEB_PERMISSIONS___`/`___SERVER_PERMISSIONS___` siano JSON valido
  (GTM li legge come tali; un refuso qui non è un errore di sintassi
  JavaScript e altrimenti si scoprirebbe solo importando il template in GTM);
- che ogni `- name:` di scenario in `___TESTS___` sia uno scalare YAML tra
  apici singoli ben formato (es. `'Costruisce l''URL...'`, con l'apice
  raddoppiato per uno letterale, `''`, non `\'`) e che il nome che ne
  risulta non contenga nessuna virgoletta doppia (`"`) letterale.
  Importando un template con una virgoletta doppia in un nome di
  scenario in un container GTM reale, l'errore è: `Test name '...' is
  invalid. The name contains invalid character: """.` — è una
  validazione propria del tab Test di GTM sul nome dello scenario,
  distinta dal parsing YAML (che accetta senza problemi una virgoletta
  doppia dentro uno scalare tra apici singoli).

Nasce da tre bug reali capitati durante lo sviluppo (una fence lasciata
aperta da una modifica, la copia incorporata rimasta disallineata senza
che un confronto manuale parziale se ne accorgesse, e i nomi di scenario
non tra apici che GTM rifiutava in importazione) — invece di scoprirli
solo rilanciando una revisione a mano, ora ogni push li segnala da solo.
Per eseguirlo in locale: `node scripts/verify-templates.js` (nessuna
dipendenza da installare, solo Node.js).

## Nomi di colonna riservati

Nella tabella "Dati da scrivere" di entrambi i tag, non usare `sheet`,
`token`, `_order`, `ping`, `_dedupe`, `timestamp` o `__proto__` come "Nome
colonna": i primi sei sono gli stessi nomi usati dal protocollo tra il tag
e Apps Script per il nome del foglio, il token, l'ordine delle colonne,
l'health-check, la deduplicazione e la colonna data/ora generata in
automatico. `__proto__` è riservato per un motivo diverso e specifico dei
template `.tpl`: il payload lato tag è costruito con un semplice oggetto
JS `{}`, e assegnargli una proprietà chiamata esattamente `__proto__` non
crea un campo dati normale — viene silenziosamente ignorato dal setter
ereditato da `Object.prototype`, quindi quel valore non arriverebbe mai ad
Apps Script (che nel frattempo creerebbe comunque la colonna
nell'intestazione, sempre vuota). Il nome colonna non può nemmeno
contenere il carattere `|` (separatore interno usato per preservare
l'ordine). Se una colonna viola una di queste regole, viene scartata con
un avviso in console invece di scrivere un dato ambiguo, farlo sparire in
silenzio, o (nel caso di un'intestazione preesistente chiamata come uno di
questi nomi) esporre il valore di controllo reale — vedi la nota di
sicurezza qui sotto.

**Nota di sicurezza**: la protezione sopra riguarda i nomi che il *tag*
può inviare. Se però un foglio avesse già, per storia pregressa, una
colonna digitata a mano con uno di questi nomi (es. una colonna letterale
chiamata "token"), Apps Script si difende comunque: `handleRequest_`
scrive sempre una cella vuota per quelle intestazioni, non il valore di
controllo vero e proprio, a prescindere da come sia nata la colonna.

## Deduplicazione eventi (opzionale)

Entrambi i tag hanno un campo facoltativo **"Chiave di deduplicazione"**
(vuoto di default, nessun cambiamento di comportamento). Se lo valorizzi
con una variabile stabile per lo stesso evento logico (es. un Event ID
che non cambia se il tag/evento viene rieseguito per un retry), `Code.gs`
scarta in silenzio una seconda richiesta con la stessa chiave arrivata
entro una finestra configurabile (menu **Sheets Logger (GTM)** → **Imposta
finestra di deduplicazione eventi**, default 5 minuti, max 6 ore — limite
di `CacheService`), rispondendo `{"ok":true,"duplicate":true}` senza
scrivere una riga.

Usa `CacheService`, non crittografia: risolve i doppioni accidentali
(retry di rete, ri-consegna di un evento in una pipeline server-side), non
è una difesa contro un attaccante — per quello serve il token. Il
controllo avviene dentro lo stesso lock usato per le scritture, quindi è
privo di corse critiche anche con richieste quasi simultanee.

**Perché non una firma HMAC con timestamp** (opzione valutata in
precedenza per rafforzare il token sul tag server-side): il sandbox GTM
non offre alcuna primitiva HMAC, solo `sha256`/`sha256Sync` senza chiave.
Costruire un HMAC a mano richiederebbe XOR byte-per-byte e hash annidati
in un ambiente senza `Buffer`/TypedArray — crittografia scritta a mano,
difficile da verificare, con un beneficio marginale nella pratica: chi
fosse già in grado di intercettare le richieste tra container server e
Apps Script avrebbe accesso più diretto al token (dalla configurazione
del tag o dai log del container) di quanto gli servirebbe romperla. Non è
stata implementata per questo.

## Verificare il deployment senza scrivere righe di prova

`Code.gs` risponde a `?token=IL_TUO_TOKEN&ping=1` (aggiunto in fondo
all'URL `/exec`) con `{"ok":true,"ping":true}`, senza scrivere alcuna
riga: utile per confermare da browser che deployment e token sono
corretti durante il setup, senza sporcare il foglio con righe di test.

## Manutenzione — archiviazione righe vecchie

`Code.gs` include un'archiviazione opzionale (menu **Sheets Logger (GTM)**
→ **Archiviazione righe vecchie**): sposta le righe con `timestamp` più
vecchio di N giorni (default 90, configurabile) in un tab
`<Foglio> - Archivio`, così i tab principali non crescono all'infinito.
Si applica a ogni tab del file che abbia una colonna `timestamp` in
intestazione — cioè ogni tab scritto da questo script, indipendentemente
da quale tag/deployment lo abbia popolato.

- **Archivia ora** → esegue subito, una tantum.
- **Imposta giorni di conservazione** → cambia la soglia (default 90 giorni).
- **Attiva/disattiva archiviazione automatica mensile** → crea/rimuove un
  trigger che esegue l'archiviazione il giorno 1 di ogni mese, verso le 3
  di notte. La prima attivazione può chiedere di autorizzare il nuovo
  permesso di gestione dei trigger: è normale, Google lo richiede una
  volta sola.

Non è necessaria perché i tag funzionino: è pulizia di manutenzione,
saltabile se il volume di righe resta basso.

## Migliorie valutate e scartate (per riferimento futuro)

- **Rate limiting** sull'endpoint (un tetto di richieste/minuto via
  `CacheService`, per limitare il danno di un token trapelato): scartato
  su richiesta, nessun limite implementato oggi.
- **Log dei tentativi con token sbagliato** (per accorgersi di un token
  trapelato o di un tentativo di indovinarlo): scartato su richiesta,
  nessun log implementato oggi.

Se in futuro servissero, sono entrambi aggiungibili senza toccare i tag
GTM — vivrebbero interamente in `apps-script/Code.gs`.

## Limiti da conoscere

**Apps Script** (vale per entrambi i tag, dato che condividono lo stesso
endpoint): l'URL `/exec` dev'essere per forza pubblico (Accesso "Chiunque"),
il token condiviso è l'unico controllo d'accesso reale. Quote giornaliere
di esecuzione di Apps Script. È una chiamata verso un servizio terzo con
dati utente: valutala nel tuo setup di consenso (tab "Consenso" del tag in
GTM) per il tag client-side.

**Tag client-side, in più**: il sandbox dei template Web non espone
`fetch`, solo `sendPixel` (GET, fire-and-forget, nessuna conferma
affidabile di scrittura riuscita). `webAppUrl` e `secretToken` finiscono
nel JS eseguito nel browser: chiunque apra gli strumenti di sviluppo li
legge in chiaro. Adblocker e ITP possono bloccare la chiamata verso domini
Google in modo non uniforme.

**Tag server-side, in più**: nessuno dei limiti sopra — `sendHttpRequest`
è una vera POST server-to-server con status/body leggibili, e URL/token non
lasciano mai il container server. Resta il limite di quote di Apps Script,
condiviso con l'altro tag se puntano allo stesso deployment.
