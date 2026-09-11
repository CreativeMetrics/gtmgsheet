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
  "displayName": "Google Sheets Writer (Server-Side)",
  "categories": ["ANALYTICS", "UTILITY"],
  "brand": {
    "id": "",
    "displayName": "",
    "thumbnail": ""
  },
  "description": "Scrive una riga in un Google Sheet chiamando in POST lo stesso Apps Script Web App usato dal tag client-side. Nessuna autenticazione alle API Google, nessun service account, nessun progetto GCP richiesto: funziona con qualunque hosting del container server (Google Cloud, Stape, self-hosted).",
  "containerContexts": ["SERVER"]
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
    "help": "Lo stesso URL /exec usato dal tag client-side (stesso deployment Apps Script, vedi apps-script/Code.gs nel repository). Nessuna Google API, nessun service account: qui è solo una chiamata HTTP verso questo endpoint."
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
    "help": "Non inventarlo a mano: apri il foglio Google, menu \"Sheets Logger (GTM)\" → \"Mostra configurazione\" (il token è generato in automatico da Apps Script, insieme a URL del Web App e nome del foglio) e incollalo qui. A differenza del tag client-side, qui il valore non transita mai verso il browser: resta nella configurazione del container server."
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
    "help": "Ogni riga diventa una colonna nel foglio (creata in automatico se non esiste ancora, gestito dall'Apps Script). Qui puoi mappare direttamente variabili di event data, es. {{Event Name}}, {{Client ID}}. Nomi riservati (non usarli come nome colonna, verrebbero scartati): sheet, token, _order, ping."
  },
  {
    "type": "CHECKBOX",
    "name": "enableLogging",
    "checkboxText": "Abilita log di debug in console (solo modalità preview/debug)",
    "simpleValueType": true,
    "defaultValue": false
  }
]


___SANDBOXED_JS_FOR_SERVER_TEMPLATE___

const encodeUriComponent = require('encodeUriComponent');
const JSON = require('JSON');
const log = require('logToConsole');
const makeString = require('makeString');
const sendHttpRequest = require('sendHttpRequest');

const webAppUrl = data.webAppUrl;
const sheetName = data.sheetName || '';
const token = data.secretToken || '';
const rows = data.rowData || [];
const debug = data.enableLogging;

// Nomi riservati dal protocollo con Apps Script: una colonna chiamata
// esattamente "sheet", "token", "_order" o "ping" verrebbe silenziosamente
// sovrascritta più sotto dal valore di controllo con lo stesso nome
// (payload.token = token, ecc.), perdendo il dato che intendevi scrivere.
// Si scarta quindi la colonna con un log, invece di perderla in silenzio.
const reserved = { sheet: 1, token: 1, _order: 1, ping: 1 };

const payload = {};
let order = '';

for (let i = 0; i < rows.length; i++) {
  const name = makeString(rows[i].column1 || '');
  if (!name) continue;
  if (reserved[name]) {
    log('Google Sheets Writer - colonna "' + name + '" ignorata: nome riservato (sheet/token/_order/ping).');
    continue;
  }

  const raw = rows[i].column2;
  // NON usare "raw || ''" al posto di questo controllo: trasformerebbe
  // valori legittimi come 0 o false in una stringa vuota indistinguibile
  // da un campo davvero assente.
  payload[name] = (raw === undefined || raw === null) ? '' : makeString(raw);
  order += (order ? '|' : '') + name;
}

payload._order = order;
if (sheetName) payload.sheet = sheetName;
if (token) payload.token = token;

const body = JSON.stringify(payload);

if (debug) {
  log('Google Sheets Writer - POST ' + webAppUrl);
  log('Google Sheets Writer - body ' + body);
}

sendHttpRequest(webAppUrl, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  timeout: 5000
}, body).then((result) => {
  let parsed = null;
  try {
    parsed = JSON.parse(result.body);
  } catch (e) {
    // risposta non JSON: trattata come fallimento sotto
  }

  if (debug) {
    log('Google Sheets Writer - status ' + result.statusCode);
    log('Google Sheets Writer - response ' + result.body);
  }

  if (result.statusCode >= 200 && result.statusCode < 300 && parsed && parsed.ok) {
    data.gtmOnSuccess();
  } else {
    log('Google Sheets Writer - errore: status ' + result.statusCode + ', body ' + result.body);
    data.gtmOnFailure();
  }
}, (error) => {
  log('Google Sheets Writer - richiesta fallita: ' + error);
  data.gtmOnFailure();
});


___SERVER_PERMISSIONS___

[
  {
    "instance": {
      "key": {
        "publicId": "send_http",
        "versionId": "1"
      },
      "param": [
        {
          "key": "allowedUrls",
          "value": {
            "type": 1,
            "string": "specific"
          }
        },
        {
          "key": "urls",
          "value": {
            "type": 2,
            "listItem": [
              {
                "type": 1,
                "string": "https://script.google.com/*"
              },
              {
                "type": 1,
                "string": "https://script.googleusercontent.com/*"
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

Tag lato **server** (container sGTM) che scrive una riga in un Google
Sheet chiamando in **POST** lo stesso Apps Script Web App usato dal tag
client-side (`web-client-tag/google-sheets-logger.tpl`), tramite
`sendHttpRequest`.

Volutamente **non** usa `getGoogleAuth` / Application Default Credentials
/ Sheets API: nessun progetto Google Cloud da configurare, nessuna Google
Sheets API da abilitare, nessun service account da condividere sul foglio.
L'unico requisito è l'Apps Script pubblicato come Web App, esattamente
come per il tag client-side — vedi `apps-script/Code.gs` nel repository
(lo stesso file, non serve una seconda versione).

## Perché farlo dal server invece che dal client, se l'Apps Script è lo stesso

- **Il token e l'URL dell'Apps Script non arrivano mai al browser.** Nel
  tag client-side, `webAppUrl` e `secretToken` finiscono nel JavaScript
  eseguito nella pagina: chiunque apra gli strumenti di sviluppo o esporti
  il container li legge in chiaro. Qui restano nella configurazione del
  container server, mai esposti a un visitatore del sito.
- **Risposta reale, non opaca.** Il tag client-side usa `sendPixel`, che
  non può leggere l'esito della richiesta in modo affidabile (Apps Script
  risponde con JSON, non un'immagine, quindi il browser la segna sempre
  come "fallita" anche a scrittura riuscita). Qui `sendHttpRequest` è una
  vera chiamata HTTP server-to-server: si legge lo status code e il body
  della risposta, quindi il tag riporta in preview un successo/fallimento
  che corrisponde a quello reale.
- **Nessun limite di lunghezza URL**: i dati viaggiano nel body JSON della
  POST, non in query string.

## Setup

1. Segui il setup Apps Script descritto in
   `web-client-tag/google-sheets-logger.tpl` (sezione Documentazione) o in
   `apps-script/Code.gs`: stesso script, stesso deployment. Nessun valore
   si scrive nel codice: apri il foglio, menu "Sheets Logger (GTM)" →
   "Imposta URL Web App" (incolla l'URL copiato da Deploy → Gestisci
   deployment — non fidarti di un URL rilevato altrove) → "Mostra
   configurazione" per leggere URL, nome del foglio e token insieme.
2. In GTM (container Server): importa questo file (Templates → New →
   menu ⋮ → Import), crea il tag, incolla lo stesso URL `/exec`, nome
   foglio e token mostrati dal menu, già usati per il tag client-side (o
   un deployment separato con i suoi valori, se preferisci tenerli
   distinti).
3. Compila la tabella "Dati da scrivere" mappando variabili di event data
   (es. `{{Event Name}}`, `{{Client ID}}`, `{{Timestamp}}`) come valore di
   ogni colonna.
4. Assegna un trigger.
5. In preview, apri l'evento → tab del tag → verifica la richiesta HTTP in
   uscita verso `script.google.com`/`script.googleusercontent.com` e lo
   status/body di risposta (`{"ok":true}` = riga scritta).

Se GTM richiede permessi aggiuntivi non presenti in questo `.tpl`
(rilevamento automatico dal codice), apri il tab **Permissions** del
template e usa il pulsante per farli rilevare/aggiornare dal codice prima
di salvare.

## Colonne e intestazione

L'allineamento colonna→valore è gestito dallo stesso Apps Script del tag
client-side (allineamento dinamico all'intestazione del foglio, con
creazione automatica delle colonne nuove): qui il template invia lo stesso
formato (`_order`, `sheet`, `token` più le coppie nome/valore), solo come
body JSON di una POST invece che come query string di una GET. Lo stesso
Apps Script neutralizza anche i valori che inizierebbero per `= + - @`
(rischio di formula injection su Sheets se un valore mappato da event data
finisce nella cella tal quale — vedi `sanitizeForSheet_` in `Code.gs`).

## Manutenzione — archiviazione righe vecchie

I tab scritti da questo tag beneficiano della stessa archiviazione
opzionale descritta in `apps-script/Code.gs` e nel README: il menu
**Sheets Logger (GTM)** → **Archiviazione righe vecchie**, aperto dal
foglio Google, sposta le righe più vecchie di N giorni in un tab
`<Foglio> - Archivio`, a mano o con un trigger automatico mensile. Non
serve configurare nulla lato tag: si applica a qualunque tab abbia una
colonna `timestamp` in intestazione.

## Sicurezza — cosa resta vero comunque

- L'endpoint Apps Script resta **pubblico** (chiunque ne conosca l'URL può
  chiamarlo): qui però l'URL non è mai esposto al browser, quindi la
  superficie di attacco pratica è molto più piccola che nel tag
  client-side. Il token condiviso resta comunque l'unico controllo
  d'accesso reale — non abbassare la guardia solo perché "è lato server".
- Quote giornaliere di esecuzione di Apps Script restano valide anche
  chiamandolo da qui.
- Nessuna dipendenza da un progetto Google Cloud specifico: funziona
  identico se il container server gira su App Engine, Cloud Run, Stape o
  altro hosting.

## Alternativa scartata volutamente: Sheets API + Application Default Credentials

Una versione precedente di questo template usava `getGoogleAuth` +
`sendHttpRequest` per chiamare direttamente `spreadsheets.values.append`
della Google Sheets API v4, senza Apps Script. Tecnicamente valida (è il
pattern documentato da Google per integrare sGTM con Sheets quando il
container gira su Google Cloud), ma richiede: abilitare la Sheets API sul
progetto GCP, individuare il service account di default del container e
condividere il foglio con quell'indirizzo, e funziona solo se il container
gira su infrastruttura Google Cloud. Questo template la sostituisce
volutamente con la chiamata all'Apps Script per evitare quel setup e quella
dipendenza da GCP; il dettaglio della via API resta comunque documentato in
`docs/no-apps-script-alternatives.md` per riferimento futuro, nel caso
serva rivalutarla.
