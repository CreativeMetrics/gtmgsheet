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
2. Incolla il contenuto di `apps-script/Code.gs`, cambia `SHARED_SECRET`.
3. Deploy → Nuovo deployment → App web → Esegui come "Me" → Accesso
   "Chiunque". Copia l'URL `/exec`.

Il codice è duplicato anche nella sezione Documentazione di
`google-sheets-logger.tpl` (`___NOTES___`), così resta visibile
direttamente dall'interfaccia GTM a chi importa il template senza dover
aprire il repository.

## Setup rapido — tag client-side

1. Completa il setup Apps Script sopra.
2. In GTM (container Web): importa `web-client-tag/google-sheets-logger.tpl`,
   crea il tag, incolla l'URL `/exec`, imposta lo stesso `SHARED_SECRET` nel
   campo "Token condiviso", compila la tabella colonna→valore, assegna un
   trigger.
3. Verifica in preview (tab della richiesta in uscita) e controlla che la
   riga compaia nel foglio.

## Setup rapido — tag server-side

1. Completa lo stesso setup Apps Script sopra (può essere lo stesso
   deployment usato dal tag client, o uno diverso).
2. In GTM (container Server): importa
   `server-side-tag/google-sheets-writer.tpl`, crea il tag, incolla lo
   stesso URL `/exec` e lo stesso token condiviso, compila la tabella
   colonna→valore mappando variabili di event data (es. `{{Event Name}}`,
   `{{Client ID}}`), assegna un trigger.
3. Verifica in preview lo status code e il body della risposta
   (`{"ok":true}` = riga scritta) verso `script.google.com` /
   `script.googleusercontent.com`.

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
