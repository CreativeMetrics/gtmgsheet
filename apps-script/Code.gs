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
 * - "sheet", "token", "_order", "ping", "_dedupe" sono nomi di colonna
 *   riservati: se la tabella del tag ne usa uno, il template GTM lo scarta
 *   con un log invece di lasciare un comportamento ambiguo o una perdita
 *   silenziosa del dato (vedi i commenti nei template .tpl).
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
    var reserved = { sheet: 1, token: 1, _order: 1, ping: 1, _dedupe: 1, timestamp: 1 };

    // Ordine dichiarato dal tag (preserva l'ordine impostato nella tabella del tag)
    var declared = String(p._order || '').split('|').filter(function (c) { return c; });

    // Eventuali parametri extra non dichiarati, aggiunti in coda
    var extras = Object.keys(p).filter(function (k) {
      return !reserved[k] && declared.indexOf(k) === -1;
    });
    var incoming = declared.concat(extras);

    // Intestazione attuale del foglio (trim difensivo: uno spazio in coda
    // digitato per errore in un'intestazione farebbe fallire il confronto
    // con i nomi di colonna dichiarati e ne creerebbe una duplicata)
    var lastCol = sheet.getLastColumn();
    var headers = lastCol > 0
      ? sheet.getRange(1, 1, 1, lastCol).getValues()[0].map(function (h) { return String(h).trim(); })
      : [];

    if (headers.length === 0 || headers.join('') === '') {
      // Foglio vuoto: crea l'intestazione la prima volta. "timestamp" è
      // già escluso da "incoming" tramite reserved, ma un filtro esplicito
      // qui protegge anche una richiesta scritta a mano (non passata dal
      // template GTM) che ignorasse quella protezione.
      headers = ['timestamp'].concat(incoming.filter(function (c) { return c !== 'timestamp'; }));
      sheet.getRange(1, 1, 1, headers.length).setValues([headers]);
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
        sheet.getRange(1, headers.length + 1, 1, missing.length).setValues([missing]);
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
    var row = headers.map(function (h) {
      if (h === 'timestamp') return new Date();
      if (reserved[h]) return '';
      return sanitizeForSheet_(p[h] !== undefined ? p[h] : '');
    });

    sheet.appendRow(row);
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

// true se questa chiave è già stata vista entro la finestra configurata
// (e la registra per la prossima volta); false alla prima occorrenza.
function isDuplicateEvent_(key) {
  var cache = CacheService.getScriptCache();
  var cacheKey = 'dedupe_' + key;
  if (cache.get(cacheKey)) return true;
  cache.put(cacheKey, '1', getDedupeWindowSeconds_());
  return false;
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

      var headers = sheet.getRange(1, 1, 1, lastCol).getValues()[0].map(function (h) { return String(h).trim(); });
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
      if (!archiveSheet) {
        archiveSheet = ss.insertSheet(archiveName);
        archiveSheet.getRange(1, 1, 1, headers.length).setValues([headers]);
      }
      archiveSheet.getRange(archiveSheet.getLastRow() + 1, 1, oldRows.length, headers.length).setValues(oldRows);

      // Elimina dal basso verso l'alto: altrimenti cancellare una riga
      // sposterebbe gli indici di quelle successive già raccolte in rowsToDelete.
      for (var j = rowsToDelete.length - 1; j >= 0; j--) {
        sheet.deleteRow(rowsToDelete[j]);
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
