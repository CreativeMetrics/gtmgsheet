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
 * - Un token condiviso per limitare l'abuso dell'endpoint pubblico.
 * - Supporta sia GET (usato dal tag client con sendPixel) sia POST
 *   (utile se in futuro passi a un Custom HTML tag con fetch()).
 */

// Imposta qui un token segreto a tua scelta. Deve combaciare con il campo
// "Token condiviso" del tag GTM. Lascialo vuoto ('') per disattivare il
// controllo (sconsigliato: l'endpoint resta comunque pubblico).
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
    } catch (err) {
      // body non JSON: si prosegue comunque con e.parameter
    }
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
