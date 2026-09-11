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
    "help": "Non inventarlo a mano: apri il foglio Google, menu \"Sheets Logger (GTM)\" → \"Mostra token attuale\" (generato in automatico da Apps Script) e incollalo qui. L'endpoint /exec è pubblico: senza questo controllo chiunque legga il container GTM può scrivere nel foglio."
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
function onOpen() {
  SpreadsheetApp.getUi()
    .createMenu('Sheets Logger (GTM)')
    .addItem('Mostra token attuale', 'showSecret')
    .addItem('Rigenera token', 'regenerateSecret')
    .addToUi();
}

function getSecret_() {
  var props = PropertiesService.getScriptProperties();
  var secret = props.getProperty('SHARED_SECRET');
  if (!secret) {
    secret = Utilities.getUuid();
    props.setProperty('SHARED_SECRET', secret);
  }
  return secret;
}

function showSecret() {
  var ui = SpreadsheetApp.getUi();
  ui.alert(
    'Token condiviso attuale',
    getSecret_() + '\n\nCopialo nel campo "Token condiviso" di entrambi i tag GTM (client e server).',
    ui.ButtonSet.OK
  );
}

function regenerateSecret() {
  var ui = SpreadsheetApp.getUi();
  var resp = ui.alert(
    'Rigenerare il token?',
    'I tag GTM configurati con il token attuale smetteranno di funzionare finché non aggiorni il campo "Token condiviso". Continuare?',
    ui.ButtonSet.YES_NO
  );
  if (resp !== ui.Button.YES) return;
  PropertiesService.getScriptProperties().setProperty('SHARED_SECRET', Utilities.getUuid());
  showSecret();
}

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
  if (getSecret_() !== p.token) {
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

4. Deploy → Nuovo deployment → tipo **App web**.
   - Esegui come: **Me**.
   - Chi ha accesso: **Chiunque** (obbligatorio: `sendPixel` non può
     inviare header di autenticazione, quindi il deployment deve essere
     pubblico; il token condiviso è l'unico controllo di accesso
     disponibile in questo scenario).
5. Copia l'URL che termina in `/exec` e incollalo nel campo "Apps Script
   Web App URL" del tag.
6. Ricarica la pagina del foglio Google (serve perché `onOpen` giri e
   crei il menu): comparirà **Sheets Logger (GTM)** nella barra dei menu.
   Clicca **Mostra token attuale**: il token viene generato al primo
   utilizzo (non c'è nulla da inventare o scrivere nel codice) e salvato
   nelle Proprietà dello script, non nel testo del file. Copialo nel
   campo "Token condiviso" del tag.
7. **Ogni volta che modifichi il codice devi ri-deployare** (Deploy →
   Gestisci deployment → Modifica → Nuova versione), altrimenti gira la
   versione precedente. Il token invece sopravvive ai redeploy: vive nelle
   Proprietà dello script, non nel codice.

## Perché lo script è "container-bound" e non prende uno Spreadsheet ID

Nelle versioni precedenti di questo pattern, il tag passava anche lo
`spreadsheetId` in query string: chiunque leggesse il container GTM poteva
quindi scrivere in **qualsiasi foglio** accessibile all'account proprietario
dello script, non solo in quello previsto. Legando lo script direttamente
al foglio (`SpreadsheetApp.getActiveSpreadsheet()` invece di
`openById(...)`) questo problema sparisce alla radice: anche conoscendo
l'URL `/exec` e il token, si può scrivere solo in questo foglio.

## Il token: come viene generato e alternative

Il token **non va inventato a mano**: la prima volta che apri il foglio
(o quando lo rigeneri dal menu "Sheets Logger (GTM)") Apps Script lo crea
con `Utilities.getUuid()` e lo salva in `PropertiesService` — non nel
testo del codice. Questo significa anche che condividere/pubblicare il
file `Code.gs` (come in questo stesso repository) non espone mai il
valore reale in uso.

Resta comunque un **bearer token statico**: chi lo intercetta o lo legge
può usarlo finché non lo rigeneri. Alternative valutate, nessuna delle
quali elimina davvero il problema in un contesto client-side:

- **Firma HMAC con timestamp** (hash del token + timestamp + payload,
  verificato lato Apps Script con una finestra di validità breve): riduce
  il rischio di replay di una richiesta intercettata, ma qui il codice è
  eseguito nel browser di ogni visitatore, quindi la logica di firma
  stessa è leggibile da chiunque ispezioni il container — non protegge il
  segreto, solo la finestra temporale in cui una richiesta copiata resta
  valida. Ha senso soprattutto sul tag **server-side**, dove il codice non
  è mai esposto al browser: se ti serve, chiedi e la implemento lì.
- **Allowlist per IP**: non disponibile — l'oggetto `e` di Apps Script non
  espone l'IP del chiamante.
- **Contenimento del danno**: lo script può solo *aggiungere righe* a
  questo foglio (mai leggere, cancellare, o toccare altri file), quindi un
  token trapelato porta al massimo a righe spam da ripulire, non a una
  perdita di dati.

Il limite di fondo resta strutturale: qualunque credenziale che debba
viaggiare fino al browser per autorizzare una chiamata è, per definizione,
leggibile da chi controlla quel browser. Se il dato non è "loggabile a
perdere" (spam accettabile nel foglio), la risposta reale è non farlo dal
client: usa il tag server-side di questo repository, dove token e URL
restano nella configurazione del container e non lasciano mai il server.

## C'è un modo per non usare affatto Apps Script?

Vedi `docs/no-apps-script-alternatives.md` nel repository per il dettaglio
completo (in questo progetto entrambi i tag, client e server, usano lo
stesso Apps Script per scelta — niente Google Cloud, niente Sheets API,
niente service account). In sintesi le alternative valutate:

- **Tag server-side con Sheets API diretta** (non usata in questo
  progetto su richiesta): autenticazione via Application Default
  Credentials del container, zero Apps Script — ma richiede un progetto
  Google Cloud e funziona solo se il container gira su App Engine/Cloud
  Run.
- **Trucco senza codice**: un Google Form ha un endpoint pubblico
  `.../formResponse` che accetta i valori delle domande via POST e crea
  una riga nel foglio "Risposte" collegato al Form — zero riga di Apps
  Script. Limiti: colonne fisse alle domande del Form, solo append, nessuna
  vera autenticazione (e qui il token generato da Apps Script sopra non è
  nemmeno applicabile, perché non c'è codice tuo che gira), comportamento
  non documentato/non garantito da Google.
- **Servizi terzi** (Sheety, SheetDB, sheet.best, Make/Zapier con
  webhook→Sheet): zero codice lato tuo, ma i dati passano su
  un'infrastruttura terza e quasi sempre a pagamento oltre soglie minime.
