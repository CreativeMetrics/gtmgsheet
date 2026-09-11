___TERMS_OF_SERVICE___

By creating or modifying this file you agree to Google Tag Manager's Community
Template Gallery Developer Terms of Service available at
https://developers.google.com/tag-manager/gallery-tos (or the versions
displayed to you when you create or modify this file, each as amended from
time to time).

___INFO___

{
  "type": "TAG",
  "id": "cvt_temp_public_id",
  "version": 1,
  "securityGroups": [],
  "displayName": "Google Sheets Logger (Client-Side)",
  "categories": ["ANALYTICS", "UTILITY"],
  "brand": {
    "id": "",
    "displayName": "",
    "thumbnail": ""
  },
  "description": "Invia dati dal browser a un Google Apps Script Web App che li scrive come riga in un Google Sheet. Usa sendPixel (GET), l'unica API di rete disponibile nel sandbox dei template web.",
  "containerContexts": ["WEB"]
}


___TEMPLATE_PARAMETERS___

[
  {
    "type": "TEXT",
    "name": "webAppUrl",
    "displayName": "Apps Script Web App URL",
    "simpleValueType": true,
    "valueValidators": [
      {
        "type": "NON_EMPTY"
      },
      {
        "type": "REGEX",
        "args": ["^https://script\\.google\\.com/macros/s/.+/exec$"]
      }
    ],
    "help": "URL che termina in /exec ottenuto da Apps Script → Deploy → Nuovo deployment → tipo “App web”. Vedi il tab Documentazione di questo template per il codice Apps Script da incollare nel foglio."
  },
  {
    "type": "TEXT",
    "name": "sheetName",
    "displayName": "Nome del foglio (tab)",
    "simpleValueType": true,
    "help": "Nome della scheda dentro lo spreadsheet, es. Foglio1. Lascia vuoto per usare la prima scheda."
  },
  {
    "type": "TEXT",
    "name": "secretToken",
    "displayName": "Token condiviso",
    "simpleValueType": true,
    "help": "Deve combaciare esattamente con la costante SHARED_SECRET impostata nell'Apps Script. L'endpoint /exec è pubblico: senza questo controllo chiunque legga il container GTM può scrivere nel foglio."
  },
  {
    "type": "SIMPLE_TABLE",
    "name": "rowData",
    "displayName": "Dati da scrivere (colonna → valore)",
    "simpleTableColumns": [
      {
        "defaultValue": "",
        "displayName": "Nome colonna",
        "name": "column1",
        "type": "TEXT"
      },
      {
        "defaultValue": "",
        "displayName": "Valore",
        "name": "column2",
        "type": "TEXT"
      }
    ],
    "help": "Ogni riga diventa una colonna nel foglio. Se la colonna non esiste ancora viene creata in coda automaticamente."
  },
  {
    "type": "CHECKBOX",
    "name": "enableLogging",
    "checkboxText": "Abilita log di debug in console (solo modalità preview/debug)",
    "simpleValueType": true,
    "defaultValue": false
  }
]


___SANDBOXED_JS_FOR_WEB_TEMPLATE___

const logToConsole = require('logToConsole');
const encodeUriComponent = require('encodeUriComponent');
const makeString = require('makeString');
const sendPixel = require('sendPixel');

const webAppUrl = data.webAppUrl;
const sheetName = data.sheetName || '';
const token = data.secretToken || '';
const rows = data.rowData || [];
const log = data.enableLogging;

let order = '';
let qs = '';

for (let i = 0; i < rows.length; i++) {
  const name = makeString(rows[i].column1 || '');
  if (!name) continue;

  const raw = rows[i].column2;
  // Importante: NON usare "raw || 'N/A'" perché trasformerebbe anche
  // 0, false e stringa vuota (valori legittimi) in "N/A".
  const val = (raw === undefined || raw === null) ? '' : makeString(raw);

  order += (order ? '|' : '') + name;
  qs += '&' + encodeUriComponent(name) + '=' + encodeUriComponent(val);
}

let url = webAppUrl + '?_order=' + encodeUriComponent(order) + qs;
if (sheetName) url += '&sheet=' + encodeUriComponent(sheetName);
if (token) url += '&token=' + encodeUriComponent(token);

if (log) {
  logToConsole('Google Sheets Logger - invio dati a: ' + url);
}

// Nota: Apps Script risponde con testo/JSON, non con un'immagine reale.
// Il browser considera quindi il "caricamento" fallito anche quando la
// riga è stata scritta correttamente, quindi non ci si affida al callback
// di sendPixel per determinare l'esito del tag: si dichiara subito il
// successo dopo l'invio (fire-and-forget), come previsto per un tag di
// logging best-effort.
sendPixel(url, data.gtmOnSuccess, data.gtmOnSuccess);


___WEB_PERMISSIONS___

[
  {
    "instance": {
      "key": {
        "publicId": "send_pixel",
        "versionId": "1"
      },
      "param": [
        {
          "key": "urls",
          "value": {
            "type": 2,
            "listItem": [
              {
                "type": 1,
                "string": "https://script.google.com/*"
              }
            ]
          }
        }
      ]
    },
    "clientAnnotations": {
      "isEditedByUser": true
    },
    "isRequired": true
  },
  {
    "instance": {
      "key": {
        "publicId": "logging",
        "versionId": "1"
      },
      "param": [
        {
          "key": "environments",
          "value": {
            "type": 1,
            "string": "debug"
          }
        }
      ]
    },
    "clientAnnotations": {
      "isEditedByUser": true
    },
    "isRequired": true
  }
]


___TESTS___

scenarios: []


___NOTES___

## Cosa fa questo template

Tag lato client (container Web) che invia i dati della tabella "Dati da
scrivere" a un Google Apps Script Web App, che li appende come riga in un
Google Sheet.

Il sandbox dei template client-side NON espone `fetch`/XHR: l'unica API di
rete disponibile è `sendPixel` (una GET senza possibilità di leggere la
risposta). Per questo motivo:

- i dati viaggiano in query string (attenzione a valori molto lunghi: il
  limite pratico degli URL è di alcune migliaia di caratteri);
- non è possibile sapere con certezza se la scrittura sul foglio è andata a
  buon fine — è un meccanismo "best effort", adatto a log ed eventi non
  critici, non a dati che non puoi permetterti di perdere.

Se ti serve affidabilità maggiore (conferma di scrittura, payload più
grandi), l'alternativa è un tag **Custom HTML** con `fetch()` in POST
(fuori dal sandbox dei template, quindi senza queste limitazioni ma anche
senza la gestione di permessi/versioning di un template).

## Setup — Apps Script (da incollare nel foglio Google)

1. Apri il Google Sheet di destinazione.
2. Estensioni → Apps Script.
3. Cancella il contenuto di `Code.gs` e incolla questo codice
   (è lo stesso file presente in `apps-script/Code.gs` nel repository):

```javascript
var SHARED_SECRET = 'CAMBIA_QUESTO_TOKEN';

function doGet(e) {
  return handleRequest_(e.parameter || {});
}

function doPost(e) {
  var params = {};
  for (var k in e.parameter) params[k] = e.parameter[k];
  if (e.postData && e.postData.type && e.postData.type.indexOf('json') !== -1) {
    try {
      var body = JSON.parse(e.postData.contents);
      for (var bk in body) params[bk] = body[bk];
    } catch (err) {}
  }
  return handleRequest_(params);
}

function handleRequest_(p) {
  if (SHARED_SECRET && p.token !== SHARED_SECRET) {
    return jsonOutput_({ ok: false, error: 'unauthorized' });
  }

  var lock = LockService.getScriptLock();
  try {
    lock.waitLock(30000);
  } catch (err) {
    return jsonOutput_({ ok: false, error: 'lock_timeout' });
  }

  try {
    var ss = SpreadsheetApp.getActiveSpreadsheet();
    var sheetName = p.sheet || ss.getSheets()[0].getName();
    var sheet = ss.getSheetByName(sheetName);
    if (!sheet) return jsonOutput_({ ok: false, error: 'sheet_not_found: ' + sheetName });

    var reserved = { sheet: 1, token: 1, _order: 1 };
    var declared = String(p._order || '').split('|').filter(function (c) { return c; });
    var extras = Object.keys(p).filter(function (k) {
      return !reserved[k] && declared.indexOf(k) === -1;
    });
    var incoming = declared.concat(extras);

    var lastCol = sheet.getLastColumn();
    var headers = lastCol > 0
      ? sheet.getRange(1, 1, 1, lastCol).getValues()[0].map(String)
      : [];

    if (headers.length === 0 || headers.join('') === '') {
      headers = ['timestamp'].concat(incoming);
      sheet.getRange(1, 1, 1, headers.length).setValues([headers]);
    } else {
      var missing = incoming.filter(function (c) { return headers.indexOf(c) === -1; });
      if (missing.length) {
        sheet.getRange(1, headers.length + 1, 1, missing.length).setValues([missing]);
        headers = headers.concat(missing);
      }
    }

    var row = headers.map(function (h) {
      if (h === 'timestamp') return new Date();
      return p[h] !== undefined ? p[h] : '';
    });

    sheet.appendRow(row);
    return jsonOutput_({ ok: true });
  } catch (err) {
    return jsonOutput_({ ok: false, error: String(err) });
  } finally {
    lock.releaseLock();
  }
}

function jsonOutput_(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);
}
```

4. Modifica `SHARED_SECRET` con un valore a tua scelta (dev'essere
   identico al campo "Token condiviso" del tag GTM).
5. Deploy → Nuovo deployment → tipo **App web**.
   - Esegui come: **Me**.
   - Chi ha accesso: **Chiunque** (obbligatorio: `sendPixel` non può
     inviare header di autenticazione, quindi il deployment deve essere
     pubblico; il token condiviso è l'unico controllo di accesso
     disponibile in questo scenario).
6. Copia l'URL che termina in `/exec` e incollalo nel campo "Apps Script
   Web App URL" del tag.
7. **Ogni volta che modifichi il codice devi ri-deployare** (Deploy →
   Gestisci deployment → Modifica → Nuova versione), altrimenti gira la
   versione precedente.

## Perché lo script è "container-bound" e non prende uno Spreadsheet ID

Nelle versioni precedenti di questo pattern, il tag passava anche lo
`spreadsheetId` in query string: chiunque leggesse il container GTM poteva
quindi scrivere in **qualsiasi foglio** accessibile all'account proprietario
dello script, non solo in quello previsto. Legando lo script direttamente
al foglio (`SpreadsheetApp.getActiveSpreadsheet()` invece di
`openById(...)`) questo problema sparisce alla radice: anche conoscendo
l'URL `/exec` e il token, si può scrivere solo in questo foglio.

## Sicurezza — cosa resta vero comunque

- L'URL `/exec` è dentro il container GTM: è per definizione **pubblico**.
  Il token condiviso alza l'asticella ma non è autenticazione vera (viaggia
  in chiaro in query string).
- Limiti giornalieri di esecuzione di Apps Script: su volumi alti li si
  raggiunge.
- Adblocker/estensioni privacy bloccano con una certa frequenza le chiamate
  verso domini Google da script di terze parti nella pagina.
- È una chiamata verso un servizio terzo con dati dell'utente: valuta il
  Consent Mode / le impostazioni di consenso del tag (tab "Consenso" del
  tag in GTM), non serve gestirlo nel codice del template.

## C'è un modo per non usare affatto Apps Script?

Sì, con dei compromessi. Vedi `docs/no-apps-script-alternatives.md` nel
repository per il dettaglio; in sintesi:

- **Meglio in assoluto**: se hai già (o puoi attivare) un container
  **server-side** GTM, usa il tag `google-sheets-writer.tpl` di questo
  stesso repository. Scrive su Sheets tramite le API Google con
  autenticazione via Application Default Credentials: zero Apps Script,
  nessun endpoint pubblico, nessun limite di Apps Script.
- **Trucco senza codice**: un Google Form ha un endpoint pubblico
  `.../formResponse` che accetta i valori delle domande via POST e crea
  una riga nel foglio "Risposte" collegato al Form — zero riga di Apps
  Script. Limiti: colonne fisse alle domande del Form, solo append, nessuna
  vera autenticazione, comportamento non documentato/non garantito da
  Google (può cambiare senza preavviso).
- **Servizi terzi** (Sheety, SheetDB, sheet.best, Make/Zapier con
  webhook→Sheet): zero codice lato tuo, ma i dati passano su
  un'infrastruttura terza e quasi sempre a pagamento oltre soglie minime.
