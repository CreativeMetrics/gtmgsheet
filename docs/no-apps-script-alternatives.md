# Esiste un modo per non usare Apps Script nello sheet?

Nota sullo stato attuale di questo repository: **entrambi** i tag
(`web-client-tag/google-sheets-logger.tpl` e
`server-side-tag/google-sheets-writer.tpl`) dipendono dallo stesso Apps
Script, per scelta esplicita — niente Google Cloud, niente Sheets API,
niente service account da configurare o condividere. Questo documento
resta come riferimento delle alternative valutate, per il caso in cui in
futuro si voglia eliminare anche l'Apps Script.

Risposta breve alla domanda del titolo: **sì, ma solo uscendo dal
client-side puro**. Per scrivere su Google Sheets senza alcuno script
serve comunque autenticarsi alle API Google in qualche modo; la domanda
vera è *dove* vive quell'autenticazione. Di seguito le opzioni, in ordine
di quanto risolvono bene il problema.

## 1. Tag server-side con Sheets API diretta (non usata in questo repo)

Se il container server-side gira su Google Cloud (App Engine o Cloud Run,
il setup "ufficiale" quando crei un container server da GTM), è possibile
eliminare del tutto l'Apps Script facendo chiamare al tag server-side
direttamente la Google Sheets API v4 (`spreadsheets.values.append`):

- L'autenticazione userebbe `getGoogleAuth` con le **Application Default
  Credentials** del container: nessuna chiave di service account da
  generare, copiare o custodire nel codice.
- L'unico passo di "autorizzazione" sarebbe condividere il foglio
  (permesso Editor) con l'indirizzo email del service account di default
  del progetto GCP — esattamente come condivideresti un foglio con un
  collega.
- Nessun endpoint pubblico esposto: tutto avverrebbe server-to-server tra
  il container e le API Google.

**Perché il template di questo repository non la usa**: richiede comunque
un setup non banale (abilitare la Sheets API sul progetto, individuare il
service account di default, condividere il foglio) ed è legata a doppio
filo a Google Cloud — non funziona se il container server-side è ospitato
altrove (es. Stape o un hosting che non espone le ADC di un progetto GCP).
Il tag `google-sheets-writer.tpl` in questo repo sceglie invece di
riutilizzare lo stesso Apps Script del tag client-side, chiamato in POST:
stesso identico setup su qualunque hosting, nessuna dipendenza da Google
Cloud. Se in futuro serve comunque questa via (es. per rimuovere del tutto
la dipendenza da Apps Script e i suoi limiti di quota), lo scheletro del
codice sandboxed è:

```javascript
const auth = getGoogleAuth({ scopes: ['https://www.googleapis.com/auth/spreadsheets'] });
const url = 'https://sheets.googleapis.com/v4/spreadsheets/' + encodeUriComponent(spreadsheetId) +
  '/values/' + encodeUriComponent(range) + ':append?valueInputOption=USER_ENTERED&insertDataOption=INSERT_ROWS';
sendHttpRequest(url, { method: 'POST', headers: {'Content-Type':'application/json'}, authorization: auth, timeout: 5000 },
  JSON.stringify({ values: [rowValues] }));
```

## 2. Il "trucco" del Google Form (zero codice, ma non un vero sostituto)

Ogni Google Form ha un endpoint pubblico non documentato ufficialmente ma
ben noto:

```
https://docs.google.com/forms/d/e/FORM_ID/formResponse
```

Se invii una richiesta (GET o POST) a questo URL con i parametri
`entry.XXXXXXXX=valore` per ogni domanda del form, Google Forms registra
una risposta **senza alcun Apps Script**, e se il Form ha come destinazione
un Google Sheet ("Risposte" → icona Sheets), quella risposta compare come
riga nel foglio in automatico.

Come si usa da GTM lato client: esattamente come il tag di questo
repository, ma puntando `sendPixel` (o un Custom HTML con `fetch`) verso
`.../formResponse` invece che verso un `/exec` di Apps Script, con i nomi
parametro `entry.NNNNNN` al posto dei nomi colonna liberi.

**Perché non lo consiglio come sostituto pieno**:

- Le colonne sono fisse alle domande del Form: aggiungere un campo nuovo
  significa modificare il Form, non semplicemente aggiungere una riga
  nella tabella del tag.
- Solo append, nessuna logica (niente header dinamici, niente lock — anche
  se Google Forms gestisce la concorrenza internamente).
- Comportamento non documentato ufficialmente: Google può cambiarlo senza
  preavviso, a differenza di un'API pubblica versionata.
- Zero autenticazione reale: chiunque trovi il `FORM_ID` (visibile nel
  container GTM) può inviare risposte, esattamente come con l'endpoint
  Apps Script — cambia solo che qui non puoi nemmeno aggiungere un token
  condiviso verificato lato server, perché non c'è codice tuo che gira.

Va bene per un caso semplice e a bassa criticità (poche colonne fisse,
nessun dato sensibile), non per un log strutturato che evolve nel tempo.

## 3. Servizi terzi (Sheety, SheetDB, sheet.best, Make/Zapier + webhook) — non usata in questo repo

Trasformano un Google Sheet in un endpoint REST senza che tu scriva
Apps Script. Comodi, ma:

- I dati passano sull'infrastruttura del servizio terzo prima di arrivare
  al foglio (valutazione privacy/GDPR da fare a parte).
- Quasi tutti hanno un piano gratuito con limiti bassi (richieste/mese) e
  diventano a pagamento oltre soglie minime.
- Aggiungono una dipendenza esterna in più nella catena, con il suo tempo
  di attivazione/latenza e un altro punto di failure da monitorare.

## Cosa fa questo repository

Usa Apps Script per entrambi i tag, chiamato in POST dal server invece che
in GET dal browser quando possibile: elimina il problema "endpoint
esposto al browser" (URL e token restano nella configurazione del
container server, mai visibili a un visitatore del sito) senza legarsi a
Google Cloud. Tieni comunque anche il tag client-side per i casi in cui ti
serva loggare qualcosa che accade solo nel browser e non arriva mai al
server (es. un errore JS, un'interazione UI che non generi come evento
verso sGTM).
