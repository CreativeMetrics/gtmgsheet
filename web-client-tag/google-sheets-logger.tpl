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
    "help": "URL che termina in /exec ottenuto da Apps Script → Deploy → Nuovo deployment → tipo “App web”. Non copiarlo da una rilevazione automatica: apri il foglio Google, menu “Sheets Logger (GTM)” → “Imposta URL Web App” e incollalo da lì (copiato dalla schermata Deploy → Gestisci deployment), poi “Mostra configurazione” per rileggerlo insieme a foglio e token. Vedi il tab Documentazione di questo template per il codice Apps Script da incollare nel foglio."
  },
  {
    "type": "TEXT",
    "name": "sheetName",
    "displayName": "Nome del foglio (tab)",
    "simpleValueType": true,
    "help": "Nome della scheda dentro lo spreadsheet, es. Foglio1. Lascia vuoto per usare la prima scheda. Il nome esatto (case-sensitive) compare nel popup \"Mostra configurazione\" del menu Apps Script, insieme agli altri fogli presenti nel file."
  },
  {
    "type": "TEXT",
    "name": "secretToken",
    "displayName": "Token condiviso",
    "simpleValueType": true,
    "help": "Non inventarlo a mano: apri il foglio Google, menu \"Sheets Logger (GTM)\" → \"Mostra configurazione\" (il token è generato in automatico da Apps Script) e incollalo qui. L'endpoint /exec è pubblico: senza questo controllo chiunque legga il container GTM può scrivere nel foglio."
  },
  {
    "type": "TEXT",
    "name": "dedupeKey",
    "displayName": "Chiave di deduplicazione (opzionale)",
    "simpleValueType": true,
    "help": "Una variabile che identifica in modo stabile lo stesso evento anche se il tag venisse rieseguito per un retry (es. un Event ID che non cambia a ogni tentativo). Se due richieste arrivano con la stessa chiave entro la finestra configurata in Apps Script (menu \"Imposta finestra di deduplicazione eventi\", default 5 minuti), la seconda viene ignorata senza scrivere una riga. Lascia vuoto per disattivare (nessuna deduplicazione, comportamento invariato)."
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
    "help": "Ogni riga diventa una colonna nel foglio. Se la colonna non esiste ancora viene creata in coda automaticamente. Nomi riservati (non usarli come nome colonna, verrebbero scartati): sheet, token, _order, ping, _dedupe, timestamp, __proto__. Il nome colonna non può contenere il carattere \"|\"."
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
const dedupeKey = data.dedupeKey || '';
const rows = data.rowData || [];
const log = data.enableLogging;

// Nomi riservati dal protocollo con Apps Script: se una colonna della
// tabella si chiamasse esattamente uno di questi, finirebbe duplicata
// nella query string insieme al parametro di controllo con lo stesso
// nome, con esito indefinito lato Apps Script (quale delle due vince
// dipende dall'ordine con cui vengono lette, nel peggiore dei casi
// rompendo l'autenticazione). "timestamp" è incluso perché è il nome
// della colonna generata automaticamente da Apps Script: usarlo anche
// come nome colonna qui creerebbe un'intestazione duplicata o farebbe
// perdere in silenzio il valore che intendevi scrivere. Si scarta quindi
// la colonna con un avviso in console, invece di lasciare il
// comportamento ambiguo.
// Array (non oggetto {nome: 1, ...}) apposta: un oggetto letterale eredita le
// proprietà di Object.prototype (constructor, toString, valueOf,
// hasOwnProperty, __proto__, ...), quindi "reserved[name]" per name ===
// 'toString' (o un altro nome ereditato) risulterebbe truthy anche se quel
// nome non è mai stato messo in "reserved" — una colonna chiamata
// legittimamente "toString" verrebbe scartata come se fosse riservata.
// "indexOf" su un array non ha questo problema.
// "__proto__" è riservato per un motivo ulteriore, specifico di questo
// protocollo: anche se qui non finisce in un oggetto JS (i dati viaggiano
// come coppie nome=valore in query string, costruite per concatenazione di
// stringa), lato Apps Script una colonna con questo nome creerebbe comunque
// un'intestazione "__proto__" nel foglio; scartarla qui evita quella
// colonna spuria fin dall'origine.
const reserved = ['sheet', 'token', '_order', 'ping', '_dedupe', 'timestamp', '__proto__'];

let order = '';
let qs = '';
// Nomi colonna già inclusi in questo invio: una colonna ripetuta nella
// tabella (stesso nome, due righe) non deve finire due volte in _order,
// perché altrimenti Apps Script creerebbe due intestazioni identiche in
// testa al foglio la prima volta che scrive — e, con due parametri
// identici in query string, solo uno dei due valori sopravvive comunque
// alla lettura di e.parameter lato Apps Script: l'altro andrebbe perso in
// silenzio. Si scarta quindi la ripetizione qui, con un avviso, invece di
// lasciare che la seconda occorrenza si perda più a valle in modo opaco.
// Array (non oggetto {}), stesso motivo di "reserved" sopra: un nome come
// "valueOf" o "hasOwnProperty" farebbe risultare "seen[name]" truthy per
// eredità da Object.prototype già alla prima occorrenza, scartando la
// colonna come falso duplicato.
const seen = [];

for (let i = 0; i < rows.length; i++) {
  const name = makeString(rows[i].column1 || '');
  if (!name) continue;
  if (reserved.indexOf(name) !== -1) {
    logToConsole('Google Sheets Logger - colonna "' + name + '" ignorata: nome riservato (sheet/token/_order/ping/_dedupe/timestamp/__proto__).');
    continue;
  }
  // "|" è il separatore usato in _order: una colonna che lo contenesse
  // spezzerebbe la ricostruzione dell'ordine lato Apps Script.
  if (name.indexOf('|') !== -1) {
    logToConsole('Google Sheets Logger - colonna "' + name + '" ignorata: non può contenere il carattere "|".');
    continue;
  }
  if (seen.indexOf(name) !== -1) {
    logToConsole('Google Sheets Logger - colonna "' + name + '" ignorata: nome già usato in una riga precedente della tabella.');
    continue;
  }
  seen.push(name);

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
if (dedupeKey) url += '&_dedupe=' + encodeUriComponent(dedupeKey);

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

scenarios:
- name: Costruisce l'URL con dati, sheet e token e invia il pixel
  code: |-
    const mockData = {
      webAppUrl: 'https://script.google.com/macros/s/ABC123/exec',
      sheetName: 'Foglio1',
      secretToken: 'test-token',
      dedupeKey: '',
      rowData: [
        { column1: 'event_name', column2: 'test_event' },
        { column1: 'value', column2: '0' }
      ],
      enableLogging: false
    };

    mock('sendPixel', (url, onSuccess, onFailure) => {
      assertThat(url.indexOf(mockData.webAppUrl) === 0).isEqualTo(true);
      assertThat(url.indexOf('_order=event_name%7Cvalue') !== -1).isEqualTo(true);
      assertThat(url.indexOf('event_name=test_event') !== -1).isEqualTo(true);
      assertThat(url.indexOf('value=0') !== -1).isEqualTo(true);
      assertThat(url.indexOf('sheet=Foglio1') !== -1).isEqualTo(true);
      assertThat(url.indexOf('token=test-token') !== -1).isEqualTo(true);
      assertThat(url.indexOf('_dedupe=') !== -1).isEqualTo(false);
      onSuccess();
    });

    runCode(mockData);

    assertApi('gtmOnSuccess').wasCalled();
    assertApi('gtmOnFailure').wasNotCalled();
- name: Una colonna chiamata "token" non finisce duplicata nell'URL
  code: |-
    const mockData = {
      webAppUrl: 'https://script.google.com/macros/s/ABC123/exec',
      sheetName: '',
      secretToken: 'real-secret',
      dedupeKey: '',
      rowData: [
        { column1: 'token', column2: 'attacker-value' },
        { column1: 'event_name', column2: 'test_event' }
      ],
      enableLogging: false
    };

    mock('sendPixel', (url, onSuccess, onFailure) => {
      const tokenOccurrences = url.split('token=').length - 1;
      assertThat(tokenOccurrences).isEqualTo(1);
      assertThat(url.indexOf('attacker-value') !== -1).isEqualTo(false);
      onSuccess();
    });

    runCode(mockData);

    assertApi('gtmOnSuccess').wasCalled();
- name: Una colonna ripetuta non finisce duplicata in _order né perde il primo valore in silenzio
  code: |-
    const mockData = {
      webAppUrl: 'https://script.google.com/macros/s/ABC123/exec',
      sheetName: '',
      secretToken: '',
      dedupeKey: '',
      rowData: [
        { column1: 'user_id', column2: 'first' },
        { column1: 'user_id', column2: 'second' }
      ],
      enableLogging: false
    };

    mock('sendPixel', (url, onSuccess, onFailure) => {
      assertThat(url.indexOf('_order=user_id') !== -1).isEqualTo(true);
      assertThat(url.indexOf('user_id|user_id') !== -1).isEqualTo(false);
      const userIdOccurrences = url.split('user_id=').length - 1;
      assertThat(userIdOccurrences).isEqualTo(1);
      assertThat(url.indexOf('user_id=first') !== -1).isEqualTo(true);
      assertThat(url.indexOf('second') !== -1).isEqualTo(false);
      onSuccess();
    });

    runCode(mockData);

    assertApi('gtmOnSuccess').wasCalled();
- name: La chiave di deduplicazione viene aggiunta quando impostata
  code: |-
    const mockData = {
      webAppUrl: 'https://script.google.com/macros/s/ABC123/exec',
      sheetName: '',
      secretToken: 'test-token',
      dedupeKey: 'evt-123',
      rowData: [],
      enableLogging: false
    };

    mock('sendPixel', (url, onSuccess, onFailure) => {
      assertThat(url.indexOf('_dedupe=evt-123') !== -1).isEqualTo(true);
      onSuccess();
    });

    runCode(mockData);

    assertApi('gtmOnSuccess').wasCalled();
- name: I valori 0 e stringa vuota non diventano N/A
  code: |-
    const mockData = {
      webAppUrl: 'https://script.google.com/macros/s/ABC123/exec',
      sheetName: '',
      secretToken: '',
      dedupeKey: '',
      rowData: [
        { column1: 'count', column2: 0 },
        { column1: 'empty', column2: '' }
      ],
      enableLogging: false
    };

    mock('sendPixel', (url, onSuccess, onFailure) => {
      assertThat(url.indexOf('count=0') !== -1).isEqualTo(true);
      assertThat(url.indexOf('N%2FA') !== -1).isEqualTo(false);
      assertThat(url.indexOf('N/A') !== -1).isEqualTo(false);
      onSuccess();
    });

    runCode(mockData);

    assertApi('gtmOnSuccess').wasCalled();
- name: sendPixel usa lo stesso callback per successo e fallimento (fire-and-forget)
  code: |-
    const mockData = {
      webAppUrl: 'https://script.google.com/macros/s/ABC123/exec',
      sheetName: '',
      secretToken: '',
      dedupeKey: '',
      rowData: [],
      enableLogging: false
    };

    mock('sendPixel', (url, onSuccess, onFailure) => {
      assertThat(onSuccess === onFailure).isEqualTo(true);
      onFailure();
    });

    runCode(mockData);

    assertApi('gtmOnSuccess').wasCalled();
    assertApi('gtmOnFailure').wasNotCalled();
- name: Una colonna chiamata "toString" (proprietà ereditata da Object.prototype, non nella lista dei nomi riservati) non viene scartata
  code: |-
    const mockData = {
      webAppUrl: 'https://script.google.com/macros/s/ABC123/exec',
      sheetName: '',
      secretToken: '',
      dedupeKey: '',
      rowData: [
        { column1: 'toString', column2: 'some_value' }
      ],
      enableLogging: false
    };

    mock('sendPixel', (url, onSuccess, onFailure) => {
      assertThat(url.indexOf('_order=toString') !== -1).isEqualTo(true);
      assertThat(url.indexOf('toString=some_value') !== -1).isEqualTo(true);
      onSuccess();
    });

    runCode(mockData);

    assertApi('gtmOnSuccess').wasCalled();
- name: Una colonna chiamata "__proto__" viene scartata come riservata
  code: |-
    const mockData = {
      webAppUrl: 'https://script.google.com/macros/s/ABC123/exec',
      sheetName: '',
      secretToken: '',
      dedupeKey: '',
      rowData: [
        { column1: '__proto__', column2: 'some_value' },
        { column1: 'event_name', column2: 'test_event' }
      ],
      enableLogging: false
    };

    mock('sendPixel', (url, onSuccess, onFailure) => {
      assertThat(url.indexOf('_order=event_name') !== -1).isEqualTo(true);
      assertThat(url.indexOf('__proto__') !== -1).isEqualTo(false);
      assertThat(url.indexOf('some_value') !== -1).isEqualTo(false);
      onSuccess();
    });

    runCode(mockData);

    assertApi('gtmOnSuccess').wasCalled();


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
/**
 * Apps Script da incollare nell'editor COLLEGATO al foglio Google Sheets
 * (dal foglio: Estensioni > Apps Script — NON un progetto standalone).
 *
 * Essendo "container-bound" (legato al foglio), lo script scrive SEMPRE
 * e SOLO nel foglio a cui è collegato: non serve passare/conoscere lo
 * Spreadsheet ID dal tag GTM, il che elimina il rischio di scrivere per
 * errore (o per abuso, visto che l'endpoint /exec è pubblico) in un
 * foglio diverso da quello previsto.
 *
 * Funzionalità:
 * - Allinea sempre i valori alla riga di intestazione (riga 1), invece
 *   di fare semplicemente appendRow(valori) nell'ordine di arrivo.
 * - Aggiunge in automatico le colonne nuove che non esistono ancora.
 * - LockService per evitare righe perse/sovrascritte con richieste simultanee.
 * - Un token condiviso, GENERATO AUTOMATICAMENTE (non va inventato né
 *   scritto a mano nel codice), per limitare l'abuso dell'endpoint pubblico.
 * - Supporta sia GET (usato dal tag client con sendPixel) sia POST
 *   (usato dal tag server-side con sendHttpRequest).
 * - Neutralizza i valori che inizierebbero per = + - @ (rischio di
 *   formula injection su Sheets, vedi sanitizeForSheet_ più sotto).
 * - Archiviazione opzionale delle righe più vecchie di N giorni in un tab
 *   "<Foglio> - Archivio" (menu "Archiviazione righe vecchie"), a mano o
 *   con un trigger automatico mensile, per non far crescere all'infinito
 *   il tab principale.
 * - Health-check: "?token=...&ping=1" risponde senza scrivere righe, utile
 *   per verificare deployment e token da browser durante il setup.
 * - "sheet", "token", "_order", "ping", "_dedupe", "__proto__" sono nomi di
 *   colonna riservati: se la tabella del tag ne usa uno, il template GTM lo
 *   scarta con un log invece di lasciare un comportamento ambiguo o una
 *   perdita silenziosa del dato (vedi i commenti nei template .tpl).
 *   "__proto__" in particolare non è un parametro di controllo del
 *   protocollo come gli altri: è riservato perché, nei template .tpl,
 *   l'oggetto JS usato per costruire il payload è un semplice {} — e
 *   assegnare "obj['__proto__'] = valore" con un valore stringa non crea
 *   una proprietà propria, viene silenziosamente ignorato dal setter
 *   ereditato da Object.prototype. Senza questa esclusione, una colonna
 *   chiamata così perderebbe il proprio valore senza alcun avviso.
 * - Deduplicazione opzionale per ID evento (campo "Chiave di
 *   deduplicazione" nel tag, vuoto di default): se la stessa chiave arriva
 *   due volte entro una finestra configurabile (default 5 minuti), la
 *   seconda richiesta viene ignorata senza scrivere una riga duplicata.
 *   Usa CacheService, non crittografia — pensata per i doppioni
 *   accidentali (retry di rete), non come difesa da un attaccante.
 *
 * CONFIGURAZIONE PER I TAG GTM — come vederla:
 * Apri il foglio Google normalmente: dopo aver salvato questo script
 * comparirà un menu "Sheets Logger (GTM)" nella barra del foglio con le
 * voci "Mostra configurazione", "Imposta URL Web App" e "Rigenera token".
 * "Mostra configurazione" riassume in un solo popup i tre valori da
 * incollare nei tag GTM (client e/o server): URL del Web App, nome del
 * foglio (tab) e token condiviso. L'URL va SEMPRE impostato a mano con
 * "Imposta URL Web App" copiandolo da Deploy > Gestisci deployment: NON
 * viene mai preso in automatico da ScriptApp.getService().getUrl(), che
 * su account Google Workspace può restituire un URL nel formato
 * .../a/TUODOMINIO/macros/s/.../exec — un endpoint diverso, con un
 * deployment ID diverso da quello del deployment pubblico reale, non
 * utilizzabile da un chiamante esterno come GTM. Token e URL vivono in
 * PropertiesService (Proprietà dello script), non nel testo del codice:
 * non finiscono per errore in un file condiviso, in un export del
 * container o in questo stesso repository.
 */

function onOpen() {
  var ui = SpreadsheetApp.getUi();
  ui.createMenu('Sheets Logger (GTM)')
    .addItem('Mostra configurazione (URL, foglio, token)', 'showConfig')
    .addItem('Imposta URL Web App', 'setWebAppUrl')
    .addItem('Rigenera token', 'regenerateSecret')
    .addItem('Imposta finestra di deduplicazione eventi', 'setDedupeWindowSeconds')
    .addSeparator()
    .addSubMenu(ui.createMenu('Archiviazione righe vecchie')
      .addItem('Archivia ora', 'archiveOldRowsNow')
      .addItem('Imposta giorni di conservazione', 'setArchiveAfterDays')
      .addItem('Attiva archiviazione automatica mensile', 'enableAutoArchiving')
      .addItem('Disattiva archiviazione automatica', 'disableAutoArchiving'))
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

// L'unico URL usato davvero (dal popup di configurazione, e quindi dai
// tag) è quello impostato a mano. ScriptApp.getService().getUrl() NON
// viene usato come valore autoritativo: ha bug noti e mai risolti da
// Google, e su account Google Workspace può restituire un URL nel
// formato .../a/TUODOMINIO/macros/s/.../exec che ha un deployment ID
// diverso da quello del deployment pubblico — non un problema di
// formato rilevabile con un controllo automatico, ma un ID sbagliato che
// sembra valido. Per questo è mostrato solo come suggerimento diagnostico
// in "Mostra configurazione", con l'avviso esplicito di verificarlo
// sempre confrontandolo con Deploy > Gestisci deployment prima di usarlo.
function getWebAppUrl_() {
  return PropertiesService.getScriptProperties().getProperty('WEBAPP_URL') || '';
}

function getAutoDetectedUrlHint_() {
  try {
    return ScriptApp.getService().getUrl() || '';
  } catch (err) {
    return '';
  }
}

function setWebAppUrl() {
  var ui = SpreadsheetApp.getUi();
  var props = PropertiesService.getScriptProperties();
  var current = props.getProperty('WEBAPP_URL') || '';
  var resp = ui.prompt(
    'URL del Web App',
    'Incolla l\'URL che termina in /exec, copiato da Deploy > Gestisci deployment ' +
      'dopo aver pubblicato questo script come App web. Non fidarti di un URL trovato ' +
      'altrove (es. rilevato in automatico): copialo sempre da quella schermata.' +
      (current ? '\n\nValore attuale: ' + current : ''),
    ui.ButtonSet.OK_CANCEL
  );
  if (resp.getSelectedButton() !== ui.Button.OK) return;

  var url = resp.getResponseText().trim();
  if (url && (url.indexOf('https://script.google.com/macros/s/') !== 0 || url.indexOf('/exec') === -1)) {
    ui.alert('URL non valido: deve iniziare con https://script.google.com/macros/s/ e terminare in /exec (non .../a/tuodominio/macros/s/...).');
    return;
  }
  if (url) {
    props.setProperty('WEBAPP_URL', url);
  } else {
    props.deleteProperty('WEBAPP_URL');
  }
  showConfig();
}

function showConfig() {
  var ui = SpreadsheetApp.getUi();
  var url = getWebAppUrl_();
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var activeName = ss.getActiveSheet().getName();
  var otherNames = ss.getSheets()
    .map(function (s) { return s.getName(); })
    .filter(function (n) { return n !== activeName; });

  var urlLine;
  if (url) {
    urlLine = url;
  } else {
    var hint = getAutoDetectedUrlHint_();
    urlLine = '(non impostato — usa "Imposta URL Web App" e incolla l\'URL da Deploy > Gestisci deployment)';
    if (hint) {
      urlLine += '\nValore intercettato automaticamente, NON VERIFICATO (spesso sbagliato, in particolare su ' +
        'account Google Workspace: può avere un deployment ID diverso da quello reale) — non usarlo senza ' +
        'averlo prima confrontato con Deploy > Gestisci deployment: ' + hint;
    }
  }

  var lines = [
    'Apps Script Web App URL:',
    urlLine,
    '',
    'Nome del foglio (tab) attivo:',
    activeName
  ];
  if (otherNames.length) {
    lines.push('Altri fogli in questo file: ' + otherNames.join(', '));
  }
  lines.push('', 'Token condiviso:', getSecret_());
  lines.push('', 'Copia questi valori nei campi corrispondenti dei tag GTM (client e/o server).');

  ui.alert('Configurazione per i tag GTM', lines.join('\n'), ui.ButtonSet.OK);
}

function regenerateSecret() {
  var ui = SpreadsheetApp.getUi();
  var resp = ui.alert(
    'Rigenerare il token?',
    'I tag GTM configurati con il token attuale smetteranno di funzionare ' +
      'finché non aggiorni il campo "Token condiviso" con il nuovo valore. Continuare?',
    ui.ButtonSet.YES_NO
  );
  if (resp !== ui.Button.YES) return;
  PropertiesService.getScriptProperties().setProperty('SHARED_SECRET', Utilities.getUuid());
  showConfig();
}

function doGet(e) {
  return handleRequest_(e.parameter || {});
}

function doPost(e) {
  // Object.create(null): niente Object.prototype in catena. Con un {}
  // normale, un body JSON che contenesse letteralmente la chiave
  // "__proto__" farebbe scattare, con "params[bk] = body[bk]" qui sotto,
  // l'accessor speciale __proto__ e cambierebbe il prototipo di "params"
  // invece di crearci semplicemente una proprietà propria — un effetto
  // collaterale che non serve a nulla di legittimo e complica solo
  // l'analisi di sicurezza. Con prototipo nullo quella chiave si comporta
  // come qualunque altra.
  var params = Object.create(null);
  for (var k in e.parameter) params[k] = e.parameter[k];

  if (e.postData && e.postData.type && e.postData.type.indexOf('json') !== -1) {
    try {
      var body = JSON.parse(e.postData.contents);
      for (var bk in body) params[bk] = body[bk];
    } catch (err) {
      // body non JSON: si prosegue comunque con e.parameter
    }
  }
  return handleRequest_(params);
}

function handleRequest_(p) {
  if (getSecret_() !== p.token) {
    return jsonOutput_({ ok: false, error: 'unauthorized' });
  }

  // Health-check: verifica che deployment e token siano corretti senza
  // scrivere né toccare il lock. Uso da browser: incolla l'URL /exec con
  // "?token=IL_TUO_TOKEN&ping=1" in fondo — risponde {"ok":true,"ping":true}
  // senza aggiungere righe al foglio.
  if (p.ping) {
    return jsonOutput_({ ok: true, ping: true });
  }

  var lock = LockService.getScriptLock();
  try {
    lock.waitLock(30000);
  } catch (err) {
    return jsonOutput_({ ok: false, error: 'lock_timeout' });
  }

  try {
    // Deduplica DENTRO il lock: se il controllo fosse prima di acquisirlo,
    // due richieste quasi simultanee con la stessa chiave potrebbero
    // superare entrambe il controllo prima che una delle due la registri.
    // Qui invece solo un'esecuzione alla volta può leggere/scrivere la
    // stessa chiave, quindi la deduplicazione è priva di questa corsa.
    //
    // Il controllo (isDuplicateEvent_) e la registrazione (markEventSeen_)
    // sono deliberatamente due passi separati: la chiave viene marcata
    // come "vista" solo DOPO che la riga è stata scritta con successo, più
    // in basso. Se la registrassimo qui (prima di risolvere il foglio e
    // scrivere la riga) e la scrittura poi fallisse per un errore
    // transitorio (foglio non trovato, quota, eccezione qualsiasi), un
    // eventuale retry con la stessa chiave entro la finestra di
    // deduplicazione troverebbe la chiave già marcata e risponderebbe
    // {"ok":true,"duplicate":true} senza che la riga sia mai stata scritta:
    // una perdita di dati silenziosa e mascherata da falso successo.
    if (p._dedupe && isDuplicateEvent_(p._dedupe)) {
      return jsonOutput_({ ok: true, duplicate: true });
    }

    var ss = SpreadsheetApp.getActiveSpreadsheet(); // sempre e solo questo foglio
    var sheetName = p.sheet || ss.getSheets()[0].getName();
    var sheet = ss.getSheetByName(sheetName);
    if (!sheet) {
      return jsonOutput_({ ok: false, error: 'sheet_not_found: ' + sheetName });
    }

    // Parametri riservati, mai trattati come nomi di colonna. "timestamp"
    // è incluso qui anche se non è un parametro di controllo: è il nome
    // che questo script usa per la propria colonna generata in automatico,
    // e trattarlo come riservato evita un'intestazione duplicata se un
    // tag (mal configurato o precedente a questa protezione) invia una
    // colonna con lo stesso nome.
    // Array (non oggetto {nome: 1, ...}) apposta: un oggetto letterale eredita
    // le proprietà di Object.prototype (constructor, toString, valueOf,
    // hasOwnProperty, __proto__, ...), quindi "reserved[c]" per c === 'toString'
    // (o uno degli altri nomi ereditati) risulterebbe truthy anche se quel nome
    // non è mai stato messo in "reserved" — una colonna chiamata legittimamente
    // "toString" verrebbe scartata come se fosse riservata. "indexOf" su un
    // array non ha questo problema.
    // "__proto__" è incluso per un motivo diverso dagli altri: qui in
    // Code.gs "p" è già sicuro da leggere (vedi Object.create(null) in
    // doPost e hasOwnProperty.call più sotto), ma i template .tpl che
    // popolano "p" costruiscono il loro payload con un semplice oggetto
    // {} — dove "obj['__proto__'] = valore" (valore stringa) non crea una
    // proprietà propria: viene silenziosamente ignorato dal setter
    // ereditato da Object.prototype. Trattarlo come riservato qui allinea
    // il comportamento (colonna scartata con un log) invece di lasciare
    // che, lato .tpl, il dato sparisca senza avviso mentre qui verrebbe
    // comunque creata una colonna di intestazione "__proto__" sempre vuota.
    var reserved = ['sheet', 'token', '_order', 'ping', '_dedupe', 'timestamp', '__proto__'];

    // Ordine dichiarato dal tag (preserva l'ordine impostato nella tabella del tag).
    // Filtrato anche qui su "reserved", non solo per "extras" più sotto: "_order"
    // è comunque un parametro HTTP come un altro per chi chiama l'endpoint
    // direttamente (non solo tramite il template GTM, che già lo filtra lato suo),
    // quindi un valore come "_order=token|foo" creerebbe altrimenti una colonna di
    // intestazione chiamata "token" (scritta sempre vuota per via del controllo su
    // "reserved" più sotto, ma comunque una colonna spuria che non dovrebbe esistere).
    // Deduplicato anche sui nomi ripetuti: entrambi i template .tpl scartano già una
    // colonna duplicata nella tabella del tag, ma un valore come "_order=foo|foo"
    // inviato direttamente all'endpoint (o da una versione precedente del template
    // senza quel controllo) creerebbe altrimenti due intestazioni "foo" identiche.
    // Array (non oggetto {}) per lo stesso motivo di "reserved" sopra: un
    // nome come "valueOf" o "hasOwnProperty" farebbe risultare
    // "seenDeclared[c]" truthy per eredità da Object.prototype anche alla
    // prima occorrenza, scartando la colonna come falso duplicato.
    var seenDeclared = [];
    var declared = String(p._order || '').split('|').filter(function (c) {
      if (!c || reserved.indexOf(c) !== -1 || seenDeclared.indexOf(c) !== -1) return false;
      seenDeclared.push(c);
      return true;
    });

    // Eventuali parametri extra non dichiarati, aggiunti in coda
    var extras = Object.keys(p).filter(function (k) {
      return reserved.indexOf(k) === -1 && declared.indexOf(k) === -1;
    });
    var incoming = declared.concat(extras);

    // Intestazione attuale del foglio (trim difensivo: uno spazio in coda
    // digitato per errore in un'intestazione farebbe fallire il confronto
    // con i nomi di colonna dichiarati e ne creerebbe una duplicata)
    var headers = getTrimmedHeaders_(sheet);

    if (headers.length === 0 || headers.join('') === '') {
      // Foglio vuoto: crea l'intestazione la prima volta. "timestamp" è
      // già escluso da "incoming" tramite reserved, ma un filtro esplicito
      // qui protegge anche una richiesta scritta a mano (non passata dal
      // template GTM) che ignorasse quella protezione.
      headers = ['timestamp'].concat(incoming.filter(function (c) { return c !== 'timestamp'; }));
      // I NOMI di colonna passano da setValues esattamente come i valori
      // di riga: senza sanitizeForSheet_ anche qui, un nome di colonna che
      // iniziasse per = + - @ (arrivato da una chiamata diretta
      // all'endpoint, non necessariamente dal template GTM che filtra i
      // nomi lato suo) diventerebbe una formula eseguita all'apertura del
      // foglio — la stessa classe di rischio che sanitizeForSheet_ esiste
      // per neutralizzare sui valori, qui applicata ai nomi di intestazione.
      sheet.getRange(1, 1, 1, headers.length).setValues([headers.map(sanitizeForSheet_)]);
      // Fissa il formato della colonna A (sempre "timestamp" qui) a
      // yyyy-mm-dd hh:mm:ss per tutta l'estensione del foglio, così ogni
      // riga futura lo eredita a prescindere da locale o formattazione
      // preesistente della cella (senza questo, un Date scritto via API
      // può apparire come numero seriale finché Sheets non lo rileva).
      // In un try/catch perché è cosmetico, non critico: un'eventuale
      // eccezione (es. foglio ridotto manualmente a una sola riga) non
      // deve impedire la scrittura della riga qui sotto.
      try {
        var formatRows = sheet.getMaxRows() - 1;
        if (formatRows > 0) {
          sheet.getRange(2, 1, formatRows, 1).setNumberFormat('yyyy-mm-dd hh:mm:ss');
        }
      } catch (fmtErr) {
        // ignorato di proposito: la formattazione è opzionale
      }
    } else {
      // Aggiunge in coda le colonne mai viste prima, senza toccare quelle esistenti
      var missing = incoming.filter(function (c) { return headers.indexOf(c) === -1; });
      if (missing.length) {
        // Vedi il commento sopra (creazione intestazione): sanitizeForSheet_
        // si applica anche qui per lo stesso motivo, sui nomi delle colonne
        // aggiunte in coda.
        sheet.getRange(1, headers.length + 1, 1, missing.length).setValues([missing.map(sanitizeForSheet_)]);
        headers = headers.concat(missing);
      }
    }

    // Costruisce la riga allineata all'intestazione (non all'ordine di arrivo),
    // neutralizzando i valori che appendRow tratterebbe come formula
    // (vedi sanitizeForSheet_ più sotto).
    //
    // IMPORTANTE: se un'intestazione esistente si chiamasse esattamente
    // "token" (o un altro nome riservato) — es. digitata a mano prima di
    // adottare questo script, o in un foglio creato con una versione
    // precedente senza questa protezione — "p[h]" leggerebbe il valore
    // di controllo vero e proprio (il token segreto, il nome del foglio,
    // ecc.) e lo scriverebbe in chiaro nella cella. Il controllo su
    // "reserved" qui blocca questo caso scrivendo una cella vuota, a
    // prescindere da cosa contenga effettivamente l'intestazione.
    //
    // "hasOwnProperty.call(p, h)" invece di "p[h] !== undefined": una
    // colonna già esistente nel foglio (creata da una richiesta precedente)
    // con un nome coincidente con una proprietà ereditata da
    // Object.prototype (es. "toString", "valueOf", "hasOwnProperty") e
    // NON valorizzata dalla richiesta corrente farebbe risultare
    // "p[h] !== undefined" vero comunque, restituendo la funzione ereditata
    // invece di una cella vuota. hasOwnProperty distingue "non presente in
    // questa richiesta" da "ereditato dal prototipo".
    var row = headers.map(function (h) {
      if (h === 'timestamp') return new Date();
      if (reserved.indexOf(h) !== -1) return '';
      return sanitizeForSheet_(Object.prototype.hasOwnProperty.call(p, h) ? p[h] : '');
    });

    sheet.appendRow(row);
    // Marca la chiave come vista solo ora che la riga è stata scritta
    // con successo (vedi il commento più sopra, prima del controllo
    // isDuplicateEvent_, sul perché i due passi sono separati).
    if (p._dedupe) {
      markEventSeen_(p._dedupe);
    }
    return jsonOutput_({ ok: true });
  } catch (err) {
    return jsonOutput_({ ok: false, error: String(err) });
  } finally {
    lock.releaseLock();
  }
}

// appendRow/setValues interpretano le stringhe esattamente come farebbe
// l'interfaccia se digitate a mano: un valore che inizia per "=" diventa
// una FORMULA eseguita quando qualcuno apre il foglio (es. per esfiltrare
// dati con IMPORTXML o per phishing con HYPERLINK) — un rischio reale,
// non teorico, perché arriva da un endpoint pubblico. Un apostrofo (')
// iniziale forza il valore a testo letterale, esattamente come se
// premessi ' prima di digitare in una cella: viene tolto dalla
// visualizzazione, il contenuto resta quello originale.
// Compromesso consapevole: prefissando anche "+", "-", "@" (blacklist
// standard OWASP contro l'injection nei fogli di calcolo, non solo "="),
// un valore numerico negativo legittimo (es. "-5") diventa testo invece
// che numero. Se ti serve che i numeri negativi restino numerici, togli
// "+-@" da questa regex e lascia solo "=".
function sanitizeForSheet_(v) {
  if (typeof v !== 'string') return v;
  return /^[=+\-@]/.test(v) ? "'" + v : v;
}

// Intestazione (riga 1) del foglio dato, con trim difensivo su ogni cella
// (uno spazio in coda digitato per errore farebbe fallire il confronto con
// i nomi di colonna attesi). Foglio senza colonne -> array vuoto. Usata sia
// da handleRequest_ (per allineare la riga in arrivo) sia da
// archiveOldRows_ (per trovare la colonna "timestamp").
function getTrimmedHeaders_(sheet) {
  var lastCol = sheet.getLastColumn();
  return lastCol > 0
    ? sheet.getRange(1, 1, 1, lastCol).getValues()[0].map(function (h) { return String(h).trim(); })
    : [];
}

// DEDUPLICA EVENTI — opzionale: attiva solo se il tag valorizza il campo
// "Chiave di deduplicazione" con una variabile stabile per lo stesso
// evento logico (es. un Event ID che non cambia se il tag/evento viene
// rieseguito per un retry di rete). Se la stessa chiave arriva due volte
// entro la finestra configurata, la seconda viene ignorata (risposta
// {"ok":true,"duplicate":true}, nessuna riga scritta). Usa CacheService,
// non crittografia: risolve i doppioni accidentali, non è una difesa
// contro un attaccante deliberato (per quello serve il token, non questo).

function getDedupeWindowSeconds_() {
  var seconds = parseInt(PropertiesService.getScriptProperties().getProperty('DEDUPE_WINDOW_SECONDS'), 10);
  // 21600 secondi (6 ore) è il TTL massimo consentito da CacheService.
  return (!isNaN(seconds) && seconds > 0) ? Math.min(seconds, 21600) : 300;
}

function setDedupeWindowSeconds() {
  var ui = SpreadsheetApp.getUi();
  var resp = ui.prompt(
    'Finestra di deduplicazione eventi',
    'Se due richieste arrivano con la stessa "Chiave di deduplicazione" entro ' +
      'questa finestra (in secondi, max 21600 = 6 ore), la seconda viene ignorata.' +
      '\n\nValore attuale: ' + getDedupeWindowSeconds_() + ' secondi.',
    ui.ButtonSet.OK_CANCEL
  );
  if (resp.getSelectedButton() !== ui.Button.OK) return;

  var seconds = parseInt(resp.getResponseText().trim(), 10);
  if (isNaN(seconds) || seconds <= 0) {
    ui.alert('Inserisci un numero di secondi intero maggiore di zero.');
    return;
  }
  PropertiesService.getScriptProperties().setProperty('DEDUPE_WINDOW_SECONDS', String(Math.min(seconds, 21600)));
  ui.alert('Impostato: finestra di deduplicazione a ' + getDedupeWindowSeconds_() + ' secondi.');
}

// true se questa chiave è già stata vista (e registrata con successo,
// tramite markEventSeen_) entro la finestra configurata; false altrimenti.
// Sola lettura: non registra nulla, così un tentativo la cui scrittura poi
// fallisce non "brucia" la chiave per un retry legittimo (vedi
// markEventSeen_ e il commento in handleRequest_).
function isDuplicateEvent_(key) {
  return !!CacheService.getScriptCache().get('dedupe_' + key);
}

// Registra la chiave come vista per la finestra di deduplicazione
// configurata. Va chiamata solo DOPO che la riga corrispondente è stata
// scritta con successo, mai prima (vedi isDuplicateEvent_ sopra).
function markEventSeen_(key) {
  CacheService.getScriptCache().put('dedupe_' + key, '1', getDedupeWindowSeconds_());
}

// ARCHIVIAZIONE RIGHE VECCHIE — opzionale, non necessaria perché i tag
// funzionino. Sposta le righe con "timestamp" più vecchio di N giorni dal
// tab principale a un tab "<Foglio> - Archivio" (creato al bisogno, con
// la stessa intestazione), così il tab principale non cresce all'infinito
// e resta scattante. Si applica a ogni tab di questo file che abbia una
// colonna "timestamp" in intestazione (cioè ogni tab scritto da questo
// script, con qualunque tag/deployment) — i tab "* - Archivio" stessi
// sono sempre esclusi, per non ri-archiviare l'archivio.

function getArchiveAfterDays_() {
  var days = parseInt(PropertiesService.getScriptProperties().getProperty('ARCHIVE_AFTER_DAYS'), 10);
  return (!isNaN(days) && days > 0) ? days : 90;
}

function setArchiveAfterDays() {
  var ui = SpreadsheetApp.getUi();
  var resp = ui.prompt(
    'Dopo quanti giorni archiviare',
    'Le righe più vecchie di questo numero di giorni verranno spostate in un tab ' +
      '"<Foglio> - Archivio" quando esegui "Archivia ora" o al passaggio del trigger ' +
      'automatico.\n\nValore attuale: ' + getArchiveAfterDays_() + ' giorni.',
    ui.ButtonSet.OK_CANCEL
  );
  if (resp.getSelectedButton() !== ui.Button.OK) return;

  var days = parseInt(resp.getResponseText().trim(), 10);
  if (isNaN(days) || days <= 0) {
    ui.alert('Inserisci un numero di giorni intero maggiore di zero.');
    return;
  }
  PropertiesService.getScriptProperties().setProperty('ARCHIVE_AFTER_DAYS', String(days));
  ui.alert('Impostato: le righe più vecchie di ' + days + ' giorni verranno archiviate.');
}

function archiveOldRowsNow() {
  SpreadsheetApp.getUi().alert('Archiviazione righe vecchie', archiveOldRows_().summary, SpreadsheetApp.getUi().ButtonSet.OK);
}

// Eseguita anche dal trigger automatico: niente SpreadsheetApp.getUi() qui
// dentro, perché un trigger headless non ha un'interfaccia a cui agganciarsi.
function archiveOldRows_() {
  var lock = LockService.getScriptLock();
  try {
    lock.waitLock(30000);
  } catch (err) {
    return { count: 0, summary: 'Archiviazione rimandata: un\'altra operazione stava scrivendo sul foglio.' };
  }

  try {
    var days = getArchiveAfterDays_();
    var cutoff = new Date(Date.now() - days * 24 * 60 * 60 * 1000);
    var ss = SpreadsheetApp.getActiveSpreadsheet();
    var archived = 0;
    var touched = [];

    ss.getSheets().forEach(function (sheet) {
      var name = sheet.getName();
      if (/ - Archivio$/.test(name)) return; // mai ri-archiviare un tab di archivio

      var lastRow = sheet.getLastRow();
      var lastCol = sheet.getLastColumn();
      if (lastRow < 2 || lastCol < 1) return; // nessuna riga di dati oltre l'intestazione

      var headers = getTrimmedHeaders_(sheet);
      var tsCol = headers.indexOf('timestamp');
      if (tsCol === -1) return; // non è un tab scritto da questo script

      var data = sheet.getRange(2, 1, lastRow - 1, lastCol).getValues();
      var oldRows = [];
      var rowsToDelete = []; // numeri di riga 1-based nel foglio sorgente

      for (var i = 0; i < data.length; i++) {
        var ts = data[i][tsCol];
        if (ts instanceof Date && ts < cutoff) {
          oldRows.push(data[i]);
          rowsToDelete.push(i + 2); // riga 1 = intestazione
        }
      }
      if (!oldRows.length) return;

      var archiveName = name + ' - Archivio';
      var archiveSheet = ss.getSheetByName(archiveName);
      var isNewArchiveSheet = !archiveSheet;
      if (isNewArchiveSheet) {
        archiveSheet = ss.insertSheet(archiveName);
      }
      // Riscrive sempre l'intestazione (invece di farlo solo alla creazione
      // del tab): se il tab principale ha guadagnato colonne dopo che
      // l'archivio esisteva già, senza questo l'intestazione dell'archivio
      // resterebbe quella vecchia, più corta, e i valori delle colonne
      // nuove finirebbero comunque scritti (nella posizione corretta) ma
      // sotto un'intestazione mancante/disallineata.
      // sanitizeForSheet_ qui non è opzionale: "headers" arriva da
      // getTrimmedHeaders_ (il valore già scritto nel foglio sorgente), non
      // da un nome appena digitato, quindi passa già per questa funzione la
      // prima volta che l'intestazione viene creata più sopra — ma qui va
      // riapplicata comunque per lo stesso motivo dei valori di riga sotto.
      archiveSheet.getRange(1, 1, 1, headers.length).setValues([headers.map(sanitizeForSheet_)]);
      if (isNewArchiveSheet) {
        // Stesso formato del tab principale per la colonna "timestamp":
        // senza questo, i valori Date spostati qui sotto rischiano di
        // apparire come numero seriale invece che come data leggibile
        // (vedi il commento analogo nella creazione dell'intestazione del
        // tab principale, più sopra in handleRequest_). In try/catch per lo
        // stesso motivo: è cosmetico, non deve bloccare l'archiviazione.
        try {
          var archiveFormatRows = archiveSheet.getMaxRows() - 1;
          if (archiveFormatRows > 0) {
            archiveSheet.getRange(2, tsCol + 1, archiveFormatRows, 1).setNumberFormat('yyyy-mm-dd hh:mm:ss');
          }
        } catch (archiveFmtErr) {
          // ignorato di proposito: la formattazione è opzionale
        }
      }
      // IMPORTANTE: "data" (quindi "oldRows") arriva da getValues() sul
      // foglio sorgente, cioè dai valori GIÀ scritti — non dai parametri
      // grezzi della richiesta HTTP. Un valore che handleRequest_ aveva
      // neutralizzato con un apostrofo iniziale (vedi sanitizeForSheet_)
      // torna da getValues() SENZA quell'apostrofo: è un prefisso
      // riconosciuto solo al momento della scrittura per forzare il testo,
      // non un carattere che resta nel valore memorizzato. Copiare quindi
      // "oldRows" così com'è in un altro foglio con setValues() rimetterebbe
      // in gioco esattamente lo stesso rischio di formula injection già
      // risolto altrove in questo file: una cella che iniziava per "=" (o
      // + - @) tornerebbe una formula eseguita all'apertura del tab di
      // archivio. sanitizeForSheet_ è un no-op sui valori non stringa (es.
      // il Date della colonna "timestamp"), quindi è sicuro applicarlo qui
      // a tutta la riga senza distinguere le colonne.
      var sanitizedOldRows = oldRows.map(function (r) {
        return r.map(sanitizeForSheet_);
      });
      archiveSheet.getRange(archiveSheet.getLastRow() + 1, 1, sanitizedOldRows.length, headers.length).setValues(sanitizedOldRows);

      // Raggruppa le righe da eliminare in intervalli contigui e chiama
      // deleteRows(inizio, quante) una volta per intervallo, invece di
      // deleteRow() una volta per riga: le righe più vecchie sono quasi
      // sempre contigue in cima al foglio (essendo le prime scritte), quindi
      // nel caso comune questo è un'unica chiamata invece di centinaia o
      // migliaia — deleteRow() ripetuto è O(n^2) perché ogni chiamata
      // risistema tutte le righe sottostanti non ancora eliminate.
      var ranges = [];
      for (var j = 0; j < rowsToDelete.length; j++) {
        var r = rowsToDelete[j];
        if (ranges.length && ranges[ranges.length - 1].end === r - 1) {
          ranges[ranges.length - 1].end = r;
        } else {
          ranges.push({ start: r, end: r });
        }
      }
      // Elimina dal basso verso l'alto: altrimenti cancellare un intervallo
      // sposterebbe gli indici di quelli successivi già calcolati in "ranges".
      for (var k = ranges.length - 1; k >= 0; k--) {
        sheet.deleteRows(ranges[k].start, ranges[k].end - ranges[k].start + 1);
      }

      archived += oldRows.length;
      touched.push(name + ' (' + oldRows.length + ')');
    });

    return {
      count: archived,
      summary: archived
        ? 'Archiviate ' + archived + ' righe più vecchie di ' + days + ' giorni: ' + touched.join(', ')
        : 'Nessuna riga più vecchia di ' + days + ' giorni da archiviare.'
    };
  } finally {
    lock.releaseLock();
  }
}

function enableAutoArchiving() {
  var ui = SpreadsheetApp.getUi();
  var already = ScriptApp.getProjectTriggers().some(function (t) {
    return t.getHandlerFunction() === 'archiveOldRowsTrigger_';
  });
  if (already) {
    ui.alert('L\'archiviazione automatica mensile è già attiva.');
    return;
  }
  ScriptApp.newTrigger('archiveOldRowsTrigger_').timeBased().onMonthDay(1).atHour(3).create();
  ui.alert(
    'Archiviazione automatica attivata: verrà eseguita il giorno 1 di ogni mese, verso le 3 di notte. ' +
      'Se richiesto, autorizza il nuovo permesso di gestione dei trigger (Google mostra il consenso solo la prima volta).'
  );
}

function disableAutoArchiving() {
  var ui = SpreadsheetApp.getUi();
  var removed = 0;
  ScriptApp.getProjectTriggers().forEach(function (t) {
    if (t.getHandlerFunction() === 'archiveOldRowsTrigger_') {
      ScriptApp.deleteTrigger(t);
      removed++;
    }
  });
  ui.alert(removed ? 'Archiviazione automatica disattivata.' : 'Non era attiva alcuna archiviazione automatica.');
}

function archiveOldRowsTrigger_() {
  archiveOldRows_();
}

function jsonOutput_(obj) {
  return ContentService
    .createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}
```

4. Deploy → Nuovo deployment → tipo **App web**.
   - Esegui come: **Me**.
   - Chi ha accesso: **Chiunque** (obbligatorio: `sendPixel` non può
     inviare header di autenticazione, quindi il deployment deve essere
     pubblico; il token condiviso è l'unico controllo di accesso
     disponibile in questo scenario).
   - Copia l'URL che termina in `/exec` mostrato a fine deploy.
5. Ricarica la pagina del foglio Google (serve perché `onOpen` giri e
   crei il menu): comparirà **Sheets Logger (GTM)** nella barra dei menu.
   - Clicca **Imposta URL Web App** e incolla l'URL copiato al punto 4.
     **Non usare un URL trovato altrove**: su account Google Workspace,
     `ScriptApp.getService().getUrl()` (l'API che tenterebbe di rilevarlo
     da sola) può restituire un URL nel formato
     `.../a/TUODOMINIO/macros/s/.../exec` con un **deployment ID diverso**
     da quello del deployment pubblico — non riconoscibile da un controllo
     di formato, perché contiene comunque `/exec`. L'unico URL corretto è
     quello copiato dalla schermata Deploy → Gestisci deployment.
   - Clicca **Mostra configurazione**: si apre un unico popup con i tre
     valori da incollare nei tag GTM — **URL del Web App** (quello appena
     impostato; se non l'hai ancora fatto, il popup può comunque mostrare
     un valore "intercettato automaticamente" a scopo diagnostico, ma è
     esplicitamente etichettato come non verificato e da non usare senza
     controllo), **nome del foglio (tab)** attivo (e l'elenco degli altri
     fogli presenti, se ce ne sono) e **token condiviso** (generato al
     primo utilizzo, non c'è nulla da inventare o scrivere nel codice).
     Copia ciascun valore nel campo corrispondente del tag: "Apps Script
     Web App URL", "Nome del foglio (tab)", "Token condiviso".
6. **Ogni volta che modifichi il codice devi ri-deployare** (Deploy →
   Gestisci deployment → Modifica → Nuova versione), altrimenti gira la
   versione precedente. **L'URL del deployment cambia solo se crei un
   nuovo deployment** (non con "Nuova versione" su uno esistente): in tal
   caso ripeti "Imposta URL Web App" con il nuovo URL copiato da Deploy →
   Gestisci deployment. Il token invece sopravvive sempre, a qualunque
   redeploy: vive nelle Proprietà dello script, non nel codice.

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
