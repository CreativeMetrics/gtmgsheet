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
docs/
  no-apps-script-alternatives.md
```

## Setup — Apps Script (comune a entrambi i tag)

1. Apri il Google Sheet di destinazione → Estensioni → Apps Script.
2. Incolla il contenuto di `apps-script/Code.gs` (nessuna costante da
   modificare: token e URL si gestiscono dal menu, vedi sotto).
3. Deploy → Nuovo deployment → App web → Esegui come "Me" → Accesso
   "Chiunque".
4. Ricarica la pagina del foglio: comparirà il menu **Sheets Logger
   (GTM)**.
   - **Mostra configurazione** → un unico popup con i tre valori pronti
     da incollare nei tag: **URL del Web App** (rilevato in automatico
     nella maggior parte dei casi via `ScriptApp.getService().getUrl()`),
     **nome del foglio (tab)** attivo (con l'elenco degli altri fogli, se
     il file ne ha più di uno) e **token condiviso** (generato al primo
     utilizzo, mai da inventare a mano).
   - **Imposta URL Web App** → solo se la rilevazione automatica manca o
     è sbagliata (bug noto di quell'API: a volte restituisce `/dev`
     invece di `/exec`, o un ID non più valido dopo un redeploy): incolla
     qui l'URL corretto, copiato da Deploy → Gestisci deployment. Un
     valore impostato così vince sempre su quello rilevato in automatico;
     lascialo vuoto per tornare alla rilevazione automatica.

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
