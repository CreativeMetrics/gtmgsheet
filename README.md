# GTM → Google Sheets

Due template GTM per scrivere dati (eventi, form, log) in un Google Sheet:

| Template | Container | File | Come autentica |
|---|---|---|---|
| **Google Sheets Logger** | Web (client-side) | [`web-client-tag/google-sheets-logger.tpl`](web-client-tag/google-sheets-logger.tpl) | Nessuna — chiama un Apps Script Web App pubblico |
| **Google Sheets Writer** | Server-side | [`server-side-tag/google-sheets-writer.tpl`](server-side-tag/google-sheets-writer.tpl) | Google Sheets API v4 con Application Default Credentials del container |

Entrambi si importano in GTM da **Templates → New → menu ⋮ → Import** (nella
Template Gallery interna al container non nella Community Gallery pubblica),
selezionando il relativo file `.tpl`.

## Quale usare

- Hai già un container **server-side**? Usa `google-sheets-writer.tpl`. Non
  serve alcun Apps Script, non c'è nessun endpoint pubblico, l'autenticazione
  è gestita dal container stesso (vedi il tab Documentazione del template
  per il setup completo).
- Ti serve loggare qualcosa che esiste **solo nel browser** e non arriva mai
  al server (es. un errore JS, un'interazione UI che non generi come evento
  verso sGTM), oppure non hai un container server-side: usa
  `google-sheets-logger.tpl`, che richiede l'Apps Script in
  [`apps-script/Code.gs`](apps-script/Code.gs) pubblicato come Web App.

Sono complementari, non alternativi: puoi tenerli entrambi nello stesso
progetto.

## Struttura del repository

```
web-client-tag/
  google-sheets-logger.tpl   ← template GTM da importare nel container Web
server-side-tag/
  google-sheets-writer.tpl   ← template GTM da importare nel container Server
apps-script/
  Code.gs                    ← script da incollare nel foglio (solo per il tag client-side)
docs/
  no-apps-script-alternatives.md
```

## Setup rapido — tag client-side

1. Apri il Google Sheet di destinazione → Estensioni → Apps Script.
2. Incolla il contenuto di `apps-script/Code.gs`, cambia `SHARED_SECRET`.
3. Deploy → Nuovo deployment → App web → Esegui come "Me" → Accesso
   "Chiunque". Copia l'URL `/exec`.
4. In GTM (container Web): importa `web-client-tag/google-sheets-logger.tpl`,
   crea il tag, incolla l'URL, imposta lo stesso `SHARED_SECRET` nel campo
   "Token condiviso", compila la tabella colonna→valore, assegna un trigger.
5. Verifica in preview (tab della richiesta in uscita) e controlla che la
   riga compaia nel foglio.

Il codice Apps Script completo è duplicato anche nella sezione
Documentazione del template stesso (`___NOTES___` nel file `.tpl`), così
resta visibile direttamente dall'interfaccia GTM a chi importa il template
senza dover aprire il repository.

## Setup rapido — tag server-side

1. Individua il service account di default del progetto GCP che ospita il
   container sGTM (App Engine o Cloud Run).
2. Abilita la Google Sheets API sullo stesso progetto.
3. Condividi il foglio con quel service account (permesso Editor).
4. In GTM (container Server): importa
   `server-side-tag/google-sheets-writer.tpl`, crea il tag, imposta
   Spreadsheet ID, nome foglio, tabella colonna→valore (qui puoi mappare
   direttamente variabili di event data), trigger a piacere.
5. Verifica in preview lo status code della richiesta verso
   `sheets.googleapis.com`.

Dettagli completi nella sezione Documentazione del template
(`___NOTES___` in `google-sheets-writer.tpl`).

## "Posso evitare del tutto Apps Script?"

Sì, con compromessi diversi a seconda della strada. Vedi
[`docs/no-apps-script-alternatives.md`](docs/no-apps-script-alternatives.md)
per il confronto completo (tag server-side, trucco Google Form, servizi
terzi). In breve: la via che elimina davvero Apps Script **e** l'endpoint
pubblico è il tag server-side di questo repository, se hai (o puoi
attivare) un container sGTM su Google Cloud.

## Limiti da conoscere

**Tag client-side**: il sandbox dei template Web non espone `fetch`, solo
`sendPixel` (GET, fire-and-forget, nessuna conferma affidabile di scrittura
riuscita). L'endpoint Apps Script `/exec` è per forza pubblico (nessuna
autenticazione via header); il token condiviso nel payload alza l'asticella
ma non è sicurezza vera. Quote giornaliere di esecuzione di Apps Script.
Adblocker e ITP possono bloccare la chiamata verso domini Google in modo
non uniforme. È una chiamata verso un servizio terzo con dati utente:
valutala nel tuo setup di consenso (tab "Consenso" del tag in GTM).

**Tag server-side**: richiede che il container giri su infrastruttura
Google Cloud (App Engine/Cloud Run) per usare le Application Default
Credentials; su hosting diverso questo meccanismo di auth non è
disponibile.
