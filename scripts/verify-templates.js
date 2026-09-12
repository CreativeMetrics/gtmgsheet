#!/usr/bin/env node
'use strict';

/**
 * Verifica di coerenza tra apps-script/Code.gs e i due template GTM
 * (.tpl), pensata per girare in CI ad ogni push/PR. Controlla esattamente
 * le due classi di problemi già capitate durante lo sviluppo di questo
 * repository:
 *
 * 1. La copia di Code.gs incorporata nella sezione ___NOTES___ di
 *    web-client-tag/google-sheets-logger.tpl deve restare byte-identica
 *    (riga per riga) al file reale apps-script/Code.gs — è successo che
 *    non lo fosse (un blocco di commento mancante), scoperto solo con una
 *    revisione manuale mirata.
 * 2. I blocchi ```javascript ... ``` nei file .tpl devono essere chiusi
 *    correttamente — è successo che una modifica lasciasse una fence
 *    markdown aperta, fondendo il codice con il testo successivo.
 *
 * In più, verifica che la sintassi JavaScript di Code.gs e delle sezioni
 * sandboxed dei due template sia valida (node --check), che le sezioni
 * ___..._ ___ obbligatorie siano tutte presenti, e che i blocchi JSON che
 * GTM stesso legge come tali (___INFO___, ___TEMPLATE_PARAMETERS___,
 * ___WEB_PERMISSIONS___/___SERVER_PERMISSIONS___) siano JSON valido — un
 * refuso qui (virgola in più, parentesi non chiusa) non è un errore di
 * sintassi JavaScript e passerebbe inosservato senza questo controllo,
 * scoprendosi solo importando il template in GTM.
 *
 * Uso: node scripts/verify-templates.js
 * Nessuna dipendenza esterna: solo Node.js standard library.
 */

const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

const repoRoot = path.resolve(__dirname, '..');

const CODE_GS_PATH = path.join(repoRoot, 'apps-script', 'Code.gs');
const CLIENT_TPL_PATH = path.join(repoRoot, 'web-client-tag', 'google-sheets-logger.tpl');
const SERVER_TPL_PATH = path.join(repoRoot, 'server-side-tag', 'google-sheets-writer.tpl');

let failed = false;

function ok(msg) {
  console.log('  OK   ' + msg);
}

function fail(msg) {
  console.error('  FAIL ' + msg);
  failed = true;
}

function readFile(p) {
  return fs.readFileSync(p, 'utf8');
}

// Righe del testo, senza l'ultima voce vuota generata da un "\n" finale
// (così confrontare due testi equivale a confrontare i loro contenuti,
// a prescindere da un a-capo finale in più o in meno).
function linesOf(text) {
  const lines = text.split('\n');
  if (lines.length && lines[lines.length - 1] === '') lines.pop();
  return lines;
}

// Estrae il testo tra due marcatori "___NOME___" su riga propria (il
// secondo marcatore è opzionale: se assente, va fino a fine file).
function extractSection(content, startMarker, endMarker) {
  const lines = content.split('\n');
  const startIdx = lines.findIndex((l) => l.trim() === startMarker);
  if (startIdx === -1) return null;
  let endIdx = lines.length;
  if (endMarker) {
    const relIdx = lines.slice(startIdx + 1).findIndex((l) => l.trim() === endMarker);
    if (relIdx !== -1) endIdx = startIdx + 1 + relIdx;
  }
  return lines.slice(startIdx + 1, endIdx).join('\n');
}

// Trova il primo blocco ```javascript ... ``` dentro un testo. Restituisce
// { code } se trovato e chiuso, { unterminated: true } se aperto ma mai
// chiuso, null se non ce n'è nessuno.
function extractFirstJsFence(text) {
  const lines = text.split('\n');
  const startIdx = lines.findIndex((l) => l.trim() === '```javascript');
  if (startIdx === -1) return null;
  const relIdx = lines.slice(startIdx + 1).findIndex((l) => l.trim() === '```');
  if (relIdx === -1) return { unterminated: true };
  const endIdx = startIdx + 1 + relIdx;
  return { code: lines.slice(startIdx + 1, endIdx).join('\n') };
}

function countFenceLines(text) {
  return (text.match(/^```/gm) || []).length;
}

function checkJsSyntax(code, label) {
  const tmpFile = path.join(
    os.tmpdir(),
    'verify-templates-' + process.pid + '-' + Date.now() + '-' + Math.random().toString(36).slice(2) + '.js'
  );
  fs.writeFileSync(tmpFile, code);
  try {
    execFileSync(process.execPath, ['--check', tmpFile], { stdio: 'pipe' });
    ok(label + ': sintassi JavaScript valida');
  } catch (err) {
    fail(label + ': sintassi JavaScript NON valida\n' + String(err.stderr || err.message).trim());
  } finally {
    fs.unlinkSync(tmpFile);
  }
}

function requireSections(content, label, markers) {
  const lines = content.split('\n');
  markers.forEach((m) => {
    if (lines.some((l) => l.trim() === m)) {
      ok(label + ': sezione ' + m + ' presente');
    } else {
      fail(label + ': sezione ' + m + ' MANCANTE');
    }
  });
}

// GTM legge ___INFO___/___TEMPLATE_PARAMETERS___/___WEB_PERMISSIONS___/
// ___SERVER_PERMISSIONS___ come JSON: un blocco malformato (virgola in
// più, parentesi non chiusa, ecc.) qui non è un errore di sintassi
// JavaScript rilevabile da checkJsSyntax (che controlla solo le sezioni
// ___SANDBOXED_JS_FOR_..._TEMPLATE___), quindi senza un controllo dedicato
// passerebbe inosservato in CI e si scoprirebbe solo importando il
// template in GTM.
function checkJsonSection(content, label, startMarker, endMarker) {
  const section = extractSection(content, startMarker, endMarker);
  if (section === null) {
    fail(label + ': impossibile estrarre ' + startMarker);
    return;
  }
  try {
    JSON.parse(section);
    ok(label + ': ' + startMarker + ' è JSON valido');
  } catch (err) {
    fail(label + ': ' + startMarker + ' NON è JSON valido — ' + err.message);
  }
}

// GTM legge ___TESTS___ come YAML nel proprio tab "Test": un nome di
// scenario "- name: ..." scritto come scalare YAML "plain" (senza
// apici) che contiene virgolette doppie letterali e/o un punto si è
// rivelato, importando il template in un container GTM reale, un caso
// che il parser YAML del tab Test rifiuta in fase di importazione (voce
// non selezionabile/errore nella lista "Setup"), pur essendo YAML
// valido per altri parser generici. Per essere sicuri, ogni "- name:"
// deve essere uno scalare a virgolette singole ben formato — es.
// 'Una colonna chiamata "token"...' oppure, per un apice letterale,
// 'Costruisce l''URL...' (l'apice si raddoppia, non si escapa con \).
function checkTestsScenarioNames(content, label) {
  const testsSection = extractSection(content, '___TESTS___', '___NOTES___');
  if (testsSection === null) {
    fail(label + ': impossibile estrarre ___TESTS___');
    return;
  }
  const lines = testsSection.split('\n');
  let count = 0;
  lines.forEach((line, idx) => {
    const m = line.match(/^- name: (.*)$/);
    if (!m) return;
    count++;
    const value = m[1];
    if (!/^'(?:[^']|'')*'$/.test(value)) {
      fail(
        label + ': lo scenario di test alla riga ' + (idx + 1) + ' di ___TESTS___ non è tra apici singoli in modo corretto (' +
          JSON.stringify(value) + '). Un nome scenario con virgolette doppie o punti scritto come scalare YAML "plain" ' +
          '(senza apici) può essere rifiutato dal tab Test di GTM in fase di importazione — vedi il commento sopra a questa funzione.'
      );
    }
  });
  if (count === 0) {
    fail(label + ': nessuno scenario "- name:" trovato in ___TESTS___');
  } else {
    ok(label + ': tutti i ' + count + ' nomi di scenario in ___TESTS___ sono correttamente tra apici singoli');
  }
}

console.log('== apps-script/Code.gs ==');
const codeGs = readFile(CODE_GS_PATH);
checkJsSyntax(codeGs, 'apps-script/Code.gs');

console.log('\n== web-client-tag/google-sheets-logger.tpl ==');
const clientTpl = readFile(CLIENT_TPL_PATH);

requireSections(clientTpl, 'web-client-tag/google-sheets-logger.tpl', [
  '___TERMS_OF_SERVICE___',
  '___INFO___',
  '___TEMPLATE_PARAMETERS___',
  '___SANDBOXED_JS_FOR_WEB_TEMPLATE___',
  '___WEB_PERMISSIONS___',
  '___TESTS___',
  '___NOTES___'
]);

checkJsonSection(clientTpl, 'web-client-tag/google-sheets-logger.tpl', '___INFO___', '___TEMPLATE_PARAMETERS___');
checkJsonSection(clientTpl, 'web-client-tag/google-sheets-logger.tpl', '___TEMPLATE_PARAMETERS___', '___SANDBOXED_JS_FOR_WEB_TEMPLATE___');
checkJsonSection(clientTpl, 'web-client-tag/google-sheets-logger.tpl', '___WEB_PERMISSIONS___', '___TESTS___');

const clientTotalFences = countFenceLines(clientTpl);
if (clientTotalFences % 2 !== 0) {
  fail('web-client-tag/google-sheets-logger.tpl: blocchi ``` non bilanciati nell\'intero file (trovati ' + clientTotalFences + ', un numero dispari indica una fence aperta e mai chiusa)');
} else {
  ok('web-client-tag/google-sheets-logger.tpl: blocchi ``` bilanciati nell\'intero file (' + clientTotalFences + ')');
}

checkTestsScenarioNames(clientTpl, 'web-client-tag/google-sheets-logger.tpl');

const clientSandbox = extractSection(clientTpl, '___SANDBOXED_JS_FOR_WEB_TEMPLATE___', '___WEB_PERMISSIONS___');
if (clientSandbox === null) {
  fail('web-client-tag/google-sheets-logger.tpl: impossibile estrarre ___SANDBOXED_JS_FOR_WEB_TEMPLATE___');
} else {
  checkJsSyntax(clientSandbox, 'web-client-tag/google-sheets-logger.tpl (SANDBOXED_JS_FOR_WEB_TEMPLATE)');
}

const clientNotes = extractSection(clientTpl, '___NOTES___', null);
if (clientNotes === null) {
  fail('web-client-tag/google-sheets-logger.tpl: impossibile estrarre ___NOTES___');
} else {
  const embedded = extractFirstJsFence(clientNotes);
  if (!embedded) {
    fail('web-client-tag/google-sheets-logger.tpl: nessun blocco ```javascript trovato nel tab NOTES (dovrebbe contenere la copia di Code.gs)');
  } else if (embedded.unterminated) {
    fail('web-client-tag/google-sheets-logger.tpl: blocco ```javascript aperto nel tab NOTES ma mai chiuso con una ``` — probabile fence rotta da una modifica precedente');
  } else {
    checkJsSyntax(embedded.code, 'web-client-tag/google-sheets-logger.tpl (copia di Code.gs incorporata in NOTES)');

    const codeGsLines = linesOf(codeGs);
    const embeddedLines = linesOf(embedded.code);

    if (codeGsLines.length !== embeddedLines.length) {
      fail(
        'web-client-tag/google-sheets-logger.tpl: la copia di Code.gs incorporata in NOTES NON è identica a apps-script/Code.gs ' +
          '(lunghezza diversa: apps-script/Code.gs ha ' + codeGsLines.length + ' righe, la copia incorporata ne ha ' + embeddedLines.length +
          '). Risincronizzala per intero: la copia deve essere byte-identica al file reale, comprese le righe iniziali.'
      );
    } else {
      let firstDiff = -1;
      for (let i = 0; i < codeGsLines.length; i++) {
        if (codeGsLines[i] !== embeddedLines[i]) { firstDiff = i; break; }
      }
      if (firstDiff === -1) {
        ok('web-client-tag/google-sheets-logger.tpl: copia di Code.gs incorporata in NOTES identica a apps-script/Code.gs (' + codeGsLines.length + ' righe)');
      } else {
        fail(
          'web-client-tag/google-sheets-logger.tpl: la copia di Code.gs incorporata in NOTES NON è identica a apps-script/Code.gs — ' +
            'prima differenza alla riga ' + (firstDiff + 1) + ':\n' +
            '    apps-script/Code.gs:      ' + JSON.stringify(codeGsLines[firstDiff]) + '\n' +
            '    copia incorporata (NOTES): ' + JSON.stringify(embeddedLines[firstDiff])
        );
      }
    }
  }
}

console.log('\n== server-side-tag/google-sheets-writer.tpl ==');
const serverTpl = readFile(SERVER_TPL_PATH);

requireSections(serverTpl, 'server-side-tag/google-sheets-writer.tpl', [
  '___TERMS_OF_SERVICE___',
  '___INFO___',
  '___TEMPLATE_PARAMETERS___',
  '___SANDBOXED_JS_FOR_SERVER_TEMPLATE___',
  '___SERVER_PERMISSIONS___',
  '___TESTS___',
  '___NOTES___'
]);

checkJsonSection(serverTpl, 'server-side-tag/google-sheets-writer.tpl', '___INFO___', '___TEMPLATE_PARAMETERS___');
checkJsonSection(serverTpl, 'server-side-tag/google-sheets-writer.tpl', '___TEMPLATE_PARAMETERS___', '___SANDBOXED_JS_FOR_SERVER_TEMPLATE___');
checkJsonSection(serverTpl, 'server-side-tag/google-sheets-writer.tpl', '___SERVER_PERMISSIONS___', '___TESTS___');

const serverTotalFences = countFenceLines(serverTpl);
if (serverTotalFences % 2 !== 0) {
  fail('server-side-tag/google-sheets-writer.tpl: blocchi ``` non bilanciati nell\'intero file (trovati ' + serverTotalFences + ')');
} else {
  ok('server-side-tag/google-sheets-writer.tpl: blocchi ``` bilanciati nell\'intero file (' + serverTotalFences + ')');
}

checkTestsScenarioNames(serverTpl, 'server-side-tag/google-sheets-writer.tpl');

const serverSandbox = extractSection(serverTpl, '___SANDBOXED_JS_FOR_SERVER_TEMPLATE___', '___SERVER_PERMISSIONS___');
if (serverSandbox === null) {
  fail('server-side-tag/google-sheets-writer.tpl: impossibile estrarre ___SANDBOXED_JS_FOR_SERVER_TEMPLATE___');
} else {
  checkJsSyntax(serverSandbox, 'server-side-tag/google-sheets-writer.tpl (SANDBOXED_JS_FOR_SERVER_TEMPLATE)');
}

console.log('');
if (failed) {
  console.error('Verifica FALLITA: correggi i punti sopra prima di procedere.');
  process.exit(1);
} else {
  console.log('Tutte le verifiche sono state superate.');
  process.exit(0);
}
