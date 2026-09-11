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
 *
 * CONFIGURAZIONE PER I TAG GTM — come vederla:
 * Apri il foglio Google normalmente: dopo aver salvato questo script
 * comparirà un menu "Sheets Logger (GTM)" nella barra del foglio con le
 * voci "Mostra configurazione", "Imposta URL Web App" e "Rigenera token".
 * "Mostra configurazione" riassume in un solo popup i tre valori da
 * incollare nei tag GTM (client e/o server): URL del Web App, nome del
 * foglio (tab) e token condiviso. Token e URL vivono in PropertiesService
 * (Proprietà dello script), non nel testo del codice: non finiscono per
 * errore in un file condiviso, in un export del container o in questo
 * stesso repository.
 */

function onOpen() {
  SpreadsheetApp.getUi()
    .createMenu('Sheets Logger (GTM)')
    .addItem('Mostra configurazione (URL, foglio, token)', 'showConfig')
    .addItem('Imposta URL Web App', 'setWebAppUrl')
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

// L'URL del Web App non si legge in modo affidabile da codice
// (ScriptApp.getService().getUrl() è noto per restituire un valore vuoto
// o sbagliato quando chiamato da un menu invece che da doGet/doPost), quindi
// lo si incolla una volta sola dopo il primo Deploy e resta salvato qui.
function setWebAppUrl() {
  var ui = SpreadsheetApp.getUi();
  var props = PropertiesService.getScriptProperties();
  var current = props.getProperty('WEBAPP_URL') || '';
  var resp = ui.prompt(
    'URL del Web App',
    'Incolla l\'URL che termina in /exec, copiato da Deploy > Gestisci deployment ' +
      'dopo aver pubblicato questo script come App web.' +
      (current ? '\n\nValore attuale: ' + current : ''),
    ui.ButtonSet.OK_CANCEL
  );
  if (resp.getSelectedButton() !== ui.Button.OK) return;

  var url = resp.getResponseText().trim();
  if (url && (url.indexOf('https://script.google.com/macros/s/') !== 0 || url.indexOf('/exec') === -1)) {
    ui.alert('URL non valido: deve iniziare con https://script.google.com/macros/s/ e terminare in /exec.');
    return;
  }
  props.setProperty('WEBAPP_URL', url);
  showConfig();
}

function showConfig() {
  var ui = SpreadsheetApp.getUi();
  var url = PropertiesService.getScriptProperties().getProperty('WEBAPP_URL');
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var activeName = ss.getActiveSheet().getName();
  var otherNames = ss.getSheets()
    .map(function (s) { return s.getName(); })
    .filter(function (n) { return n !== activeName; });

  var lines = [
    'Apps Script Web App URL:',
    url || '(non impostato — usa "Imposta URL Web App" dopo il Deploy)',
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
  var params = {};
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

  var lock = LockService.getScriptLock();
  try {
    lock.waitLock(30000);
  } catch (err) {
    return jsonOutput_({ ok: false, error: 'lock_timeout' });
  }

  try {
    var ss = SpreadsheetApp.getActiveSpreadsheet(); // sempre e solo questo foglio
    var sheetName = p.sheet || ss.getSheets()[0].getName();
    var sheet = ss.getSheetByName(sheetName);
    if (!sheet) {
      return jsonOutput_({ ok: false, error: 'sheet_not_found: ' + sheetName });
    }

    // Parametri riservati, mai trattati come nomi di colonna
    var reserved = { sheet: 1, token: 1, _order: 1 };

    // Ordine dichiarato dal tag (preserva l'ordine impostato nella tabella del tag)
    var declared = String(p._order || '').split('|').filter(function (c) { return c; });

    // Eventuali parametri extra non dichiarati, aggiunti in coda
    var extras = Object.keys(p).filter(function (k) {
      return !reserved[k] && declared.indexOf(k) === -1;
    });
    var incoming = declared.concat(extras);

    // Intestazione attuale del foglio
    var lastCol = sheet.getLastColumn();
    var headers = lastCol > 0
      ? sheet.getRange(1, 1, 1, lastCol).getValues()[0].map(String)
      : [];

    if (headers.length === 0 || headers.join('') === '') {
      // Foglio vuoto: crea l'intestazione la prima volta
      headers = ['timestamp'].concat(incoming);
      sheet.getRange(1, 1, 1, headers.length).setValues([headers]);
    } else {
      // Aggiunge in coda le colonne mai viste prima, senza toccare quelle esistenti
      var missing = incoming.filter(function (c) { return headers.indexOf(c) === -1; });
      if (missing.length) {
        sheet.getRange(1, headers.length + 1, 1, missing.length).setValues([missing]);
        headers = headers.concat(missing);
      }
    }

    // Costruisce la riga allineata all'intestazione (non all'ordine di arrivo)
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
  return ContentService
    .createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}
