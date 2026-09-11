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
  "description": "Scrive una riga in un Google Sheet chiamando direttamente la Google Sheets API v4 (spreadsheets.values.append), autenticandosi con le Application Default Credentials del container server (nessun Apps Script, nessun endpoint pubblico, nessuna chiave di service account da gestire).",
  "containerContexts": ["SERVER"]
}


___TEMPLATE_PARAMETERS___

[
  {
    "type": "TEXT",
    "name": "spreadsheetId",
    "displayName": "Spreadsheet ID",
    "simpleValueType": true,
    "valueValidators": [
      {
        "type": "NON_EMPTY"
      }
    ],
    "help": "L'ID nel URL del foglio: https://docs.google.com/spreadsheets/d/QUESTO_ID/edit. A differenza del tag client-side, qui è sicuro impostarlo come configurazione del tag: non transita mai verso il browser."
  },
  {
    "type": "TEXT",
    "name": "sheetName",
    "displayName": "Nome del foglio (tab)",
    "simpleValueType": true,
    "defaultValue": "Foglio1",
    "valueValidators": [
      {
        "type": "NON_EMPTY"
      }
    ]
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
    "help": "Ogni riga della tabella è una colonna del foglio, nell'ordine in cui la elenchi qui. A differenza del client-side, qui puoi mappare direttamente variabili di event data (es. {{Event Name}}, {{Client ID}}) come valore."
  },
  {
    "type": "SELECT",
    "name": "valueInputOption",
    "displayName": "Interpretazione valori",
    "selectItems": [
      {
        "value": "USER_ENTERED",
        "displayValue": "Come se digitati a mano (formule, date e numeri interpretati)"
      },
      {
        "value": "RAW",
        "displayValue": "Testo grezzo (nessuna interpretazione)"
      }
    ],
    "simpleValueType": true,
    "defaultValue": "USER_ENTERED"
  },
  {
    "type": "CHECKBOX",
    "name": "logToConsoleEnabled",
    "checkboxText": "Abilita log di debug in console (solo modalità preview/debug)",
    "simpleValueType": true,
    "defaultValue": false
  }
]


___SANDBOXED_JS_FOR_SERVER_TEMPLATE___

const encodeUriComponent = require('encodeUriComponent');
const getGoogleAuth = require('getGoogleAuth');
const JSON = require('JSON');
const log = require('logToConsole');
const makeString = require('makeString');
const sendHttpRequest = require('sendHttpRequest');
const Promise = require('Promise');

const spreadsheetId = data.spreadsheetId;
const sheetName = data.sheetName || 'Foglio1';
const rows = data.rowData || [];
const valueInputOption = data.valueInputOption || 'USER_ENTERED';
const debug = data.logToConsoleEnabled;

const values = [];
for (let i = 0; i < rows.length; i++) {
  const raw = rows[i].column2;
  values.push((raw === undefined || raw === null) ? '' : makeString(raw));
}

const auth = getGoogleAuth({
  scopes: ['https://www.googleapis.com/auth/spreadsheets']
});

const range = sheetName + '!A1';
const url = 'https://sheets.googleapis.com/v4/spreadsheets/' +
  encodeUriComponent(spreadsheetId) +
  '/values/' + encodeUriComponent(range) +
  ':append?valueInputOption=' + encodeUriComponent(valueInputOption) +
  '&insertDataOption=INSERT_ROWS';

const body = JSON.stringify({ values: [values] });

if (debug) {
  log('Google Sheets Writer - POST ' + url);
  log('Google Sheets Writer - body ' + body);
}

sendHttpRequest(url, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  authorization: auth,
  timeout: 5000
}, body).then((result) => {
  if (debug) {
    log('Google Sheets Writer - status ' + result.statusCode);
    log('Google Sheets Writer - response ' + result.body);
  }
  if (result.statusCode >= 200 && result.statusCode < 300) {
    data.gtmOnSuccess();
  } else {
    log('Google Sheets Writer - errore HTTP ' + result.statusCode + ': ' + result.body);
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
                "string": "https://sheets.googleapis.com/*"
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
Sheet chiamando direttamente `spreadsheets.values.append` della Google
Sheets API v4, autenticandosi con `getGoogleAuth` (Application Default
Credentials del container), letto tramite `sendHttpRequest`.

Nessun Apps Script, nessun endpoint `/exec` pubblico, nessuna chiave JSON
di service account da generare o custodire: è lo stesso pattern usato
dalle guide ufficiali per integrare sGTM con Google Sheets/BigQuery quando
il container gira su infrastruttura Google Cloud (App Engine o Cloud Run).

## Requisito: il container deve girare su Google Cloud

`getGoogleAuth` con `authType` di default (ADC, Application Default
Credentials) funziona perché il runtime del container server-side gira
dentro un progetto GCP e ha un service account di default associato
(App Engine o Compute Engine/Cloud Run). **Se il tuo container non gira
su infrastruttura Google Cloud tua** (es. hosting gestito da terzi che non
espone questo meccanismo), questo approccio non è applicabile: in quel caso
la strada è un tag già pronto che gestisce l'autenticazione lui stesso
(es. il tag Google Sheets di Stape, che usa una propria connessione OAuth),
non questo template.

## Setup

1. **Individua il service account di default** del progetto GCP che ospita
   il container sGTM:
   - App Engine: `NOME-PROGETTO@appspot.gserviceaccount.com`
   - Cloud Run / Compute Engine: `NUMERO-PROGETTO-compute@developer.gserviceaccount.com`

   Lo trovi in Google Cloud Console → IAM e amministrazione → Account di
   servizio, oppure nei dettagli dell'istanza App Engine/Cloud Run.

2. **Abilita la Google Sheets API** nello stesso progetto GCP (Cloud
   Console → API e servizi → Libreria → "Google Sheets API" → Abilita).

3. **Condividi il foglio** con quel service account, con permesso
   **Editor** (Condividi → incolla l'indirizzo email del service account).
   Questo sostituisce completamente qualunque gestione di credenziali nel
   codice del tag: l'autorizzazione vive interamente nella condivisione del
   file su Google Drive/Sheets.

4. In GTM, aggiungi il template (Templates → New → Import → seleziona
   questo file `.tpl`), crea il tag, imposta:
   - **Spreadsheet ID**: l'ID nell'URL del foglio.
   - **Nome del foglio**: il nome esatto della scheda (case-sensitive).
   - **Dati da scrivere**: una riga per colonna, con il valore mappato a
     variabili di event data (es. `{{Event Name}}`, `{{Client ID}}`,
     `{{Timestamp}}`).
   - Trigger a piacere (es. su tutti gli eventi, o solo su eventi
     specifici che vuoi loggare).

5. In **preview**, apri l'evento → tab del tag → verifica la richiesta
   HTTP in uscita verso `sheets.googleapis.com` e lo status code (200/201
   = riga scritta). Se GTM richiede permessi aggiuntivi non presenti in
   questo `.tpl` (rilevamento automatico dal codice), apri il tab
   **Permissions** del template e usa il pulsante per farli rilevare/
   aggiornare dal codice prima di salvare.

## Colonne e intestazione

A differenza del tag client-side, questo template **non gestisce da solo
l'allineamento con l'intestazione del foglio**: scrive i valori nell'ordine
in cui li elenchi nella tabella "Dati da scrivere", a partire dalla colonna
A. Se l'ordine delle colonne nel foglio cambia manualmente, aggiorna di
conseguenza l'ordine nel tag. Questo è volutamente più semplice del tag
client-side perché qui non c'è motivo di ricostruire dinamicamente
l'intestazione: la tabella del tag è già la fonte di verità e la modifichi
direttamente in GTM quando serve.

## Sicurezza

- Nessun endpoint pubblico: la scrittura avviene interamente
  server-to-server tra il container sGTM e le API Google.
- L'unico punto di accesso è la condivisione del foglio con il service
  account: revocarla blocca immediatamente la scrittura.
- `spreadsheetId` qui è configurazione del tag, non un parametro che
  transita verso il browser: nessun rischio di scrittura in fogli non
  previsti da parte di terzi che leggano il container.
