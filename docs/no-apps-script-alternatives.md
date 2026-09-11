# Esiste un modo per non usare Apps Script nello sheet?

Risposta breve: **sì, ma solo uscendo dal client-side puro**. Per scrivere
su Google Sheets serve sempre autenticarsi alle API Google in qualche modo;
la domanda vera è *dove* vive quell'autenticazione. Di seguito le opzioni,
in ordine di quanto risolvono bene il problema.

## 1. Passa al tag server-side (`server-side-tag/google-sheets-writer.tpl`) — consigliata

Se hai già (o puoi attivare) un container **server-side GTM** che gira su
Google Cloud (App Engine o Cloud Run, cioè il setup "ufficiale" quando crei
un container server da GTM), non ti serve alcun Apps Script:

- Il tag server-side chiama direttamente la Google Sheets API v4
  (`spreadsheets.values.append`).
- L'autenticazione usa `getGoogleAuth` con le **Application Default
  Credentials** del container: nessuna chiave di service account da
  generare, copiare o custodire nel codice.
- L'unico passo di "autorizzazione" è condividere il foglio (permesso
  Editor) con l'indirizzo email del service account di default del
  progetto GCP — esattamente come condivideresti un foglio con un
  collega.
- Nessun endpoint pubblico esposto: tutto avviene server-to-server tra il
  tuo container e le API Google.

Vedi le istruzioni complete nel tab Documentazione del template
(`server-side-tag/google-sheets-writer.tpl`, sezione `___NOTES___`).

**Limite**: funziona perché il container gira su infrastruttura Google
Cloud. Se il tuo sGTM è ospitato altrove (es. un hosting terzo che non
espone le Application Default Credentials di un progetto GCP), questo
meccanismo di autenticazione non è disponibile: in quel caso la strada
realistica è un tag già pronto che gestisce da solo l'autenticazione verso
Google (es. il tag Google Sheets di Stape, con una propria connessione
OAuth), non un template scritto da zero.

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

## 3. Servizi terzi (Sheety, SheetDB, sheet.best, Make/Zapier + webhook)

Trasformano un Google Sheet in un endpoint REST senza che tu scriva
Apps Script. Comodi, ma:

- I dati passano sull'infrastruttura del servizio terzo prima di arrivare
  al foglio (valutazione privacy/GDPR da fare a parte).
- Quasi tutti hanno un piano gratuito con limiti bassi (richieste/mese) e
  diventano a pagamento oltre soglie minime.
- Aggiungono una dipendenza esterna in più nella catena, con il suo tempo
  di attivazione/latenza e un altro punto di failure da monitorare.

## Cosa farei io

Se hai già il container server-side (e dal contesto sembra di sì, visto
che lo usi già per le trasformazioni PII): usa il tag server-side di
questo repository. Risolve alla radice sia il problema "niente Apps
Script" sia il problema "endpoint pubblico scrivibile da chiunque" del
tag client-side. Tieni comunque anche il tag client-side per i casi in cui
ti serva loggare qualcosa che accade solo nel browser e non arriva mai al
server (es. un errore JS, un'interazione UI che non generi come evento
verso sGTM).
