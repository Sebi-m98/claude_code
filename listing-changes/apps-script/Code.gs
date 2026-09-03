/**
 * Listing Changes Timeline – Apps Script (an das ASIN-Tracker-Sheet gebunden)
 *
 * Einrichtung (einmalig, ca. 3 Minuten):
 *  1. Im Sheet: Erweiterungen → Apps Script
 *  2. Inhalt von Code.gs hier einfügen (Datei "Code.gs")
 *  3. Datei → Neu → HTML, Name "Index", Inhalt von Index.html einfügen
 *  4. Speichern, Sheet neu laden → Menü "ASIN-Tracker" → "Changes Timeline"
 *
 * Optional als eigene Seite: Bereitstellen → Neue Bereitstellung → Web-App
 * (Ausführen als: ich, Zugriff: nur ich). Die URL öffnet die Timeline im Vollbild.
 */

var SHEET_CHANGES = 'Changes';
var SHEET_ASINS = 'ASINs';

function onOpen() {
  SpreadsheetApp.getUi()
    .createMenu('ASIN-Tracker')
    .addItem('Changes Timeline', 'showTimeline')
    .addToUi();
}

function showTimeline() {
  var html = HtmlService.createHtmlOutputFromFile('Index')
    .setWidth(1400)
    .setHeight(900)
    .setTitle('Listing Changes');
  SpreadsheetApp.getUi().showModalDialog(html, 'Listing Changes');
}

function doGet() {
  return HtmlService.createHtmlOutputFromFile('Index')
    .setTitle('Listing Changes')
    .setXFrameOptionsMode(HtmlService.XFrameOptionsMode.ALLOWALL);
}

/** Liefert {data, asins} im Format, das app.js erwartet. */
function getData() {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var chSheet = ss.getSheetByName(SHEET_CHANGES);
  var values = chSheet.getDataRange().getValues();
  var head = values.shift().map(function (h) { return String(h).trim().toLowerCase(); });
  var col = function (name) { return head.indexOf(name); };
  var iDate = col('date'), iAsin = col('asin'), iProd = col('produkt'), iField = col('field_name'),
      iOld = col('old_value'), iNew = col('new_value'), iComp = col('competitor zu asin'),
      iCompP = col('competitor zu produkt'), iMp = col('marketplace');

  var changes = [];
  var maxDate = '';
  values.forEach(function (r) {
    if (!r[iAsin] || !r[iDate]) return;
    var d = toIso(r[iDate]);
    if (d > maxDate) maxDate = d;
    changes.push({
      date: d,
      asin: String(r[iAsin]).trim(),
      product: String(r[iProd] || ''),
      field: String(r[iField] || '').trim(),
      old: cell(r[iOld]),
      'new': cell(r[iNew]),
      compOf: iComp >= 0 ? String(r[iComp] || '').trim() : '',
      compOfProduct: iCompP >= 0 ? String(r[iCompP] || '') : '',
      marketplace: iMp >= 0 ? String(r[iMp] || '').trim() : ''
    });
  });

  var own = [], competitors = [];
  var aSheet = ss.getSheetByName(SHEET_ASINS);
  if (aSheet) {
    var av = aSheet.getDataRange().getValues();
    var ah = av.shift().map(function (h) { return String(h).trim(); });
    var ia = ah.indexOf('ASIN'), ip = ah.indexOf('Produkt');
    av.forEach(function (r) {
      var asin = String(r[ia] || '').trim();
      if (!asin) return;
      own.push({ asin: asin, title: String(r[ip] || '') });
      for (var k = 1; k <= 5; k++) {
        var ik = ah.indexOf('K' + k + '_ASIN'), ikp = ah.indexOf('K' + k + '_Produkt');
        var ka = ik >= 0 ? String(r[ik] || '').trim() : '';
        if (ka) competitors.push({ asin: ka, compOf: asin, title: ikp >= 0 ? String(r[ikp] || '') : '' });
      }
    });
  }

  var today = Utilities.formatDate(new Date(), ss.getSpreadsheetTimeZone(), 'yyyy-MM-dd');
  return {
    data: { exportedAt: today > maxDate ? today : maxDate, changes: changes },
    asins: { own: own, competitors: competitors }
  };
}

function toIso(v) {
  if (v instanceof Date) {
    return Utilities.formatDate(v, SpreadsheetApp.getActiveSpreadsheet().getSpreadsheetTimeZone(), 'yyyy-MM-dd');
  }
  return String(v).slice(0, 10);
}

function cell(v) {
  if (v === null || v === undefined) return '';
  if (typeof v === 'number') return String(v);
  return String(v);
}
