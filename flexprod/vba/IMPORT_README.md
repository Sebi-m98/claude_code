# FlexProd Schaltzettel v2.7 - VBA Import-Anleitung

Diese Anleitung beschreibt, wie die optimierte v2.7 in Excel scharfgeschaltet wird.

## Was ist neu in v2.7

- **Entfernt**: Sortier-Button, Min/Max-Buttons, Search&Replace-Bugfix, Leerzeile-Funktion
- **Geaendert**: Zurue-Ltg-Button ist jetzt ein Toggle (Ein/Aus) - 1 Klick blendet Zurue-Leitungen aus, naechster Klick blendet sie wieder ein. Daten gehen nicht mehr verloren.
- **Neu**:
  - **Umschaltung mit Anzahl-Stifte-Limit**: bei jeder Umschaltung-Variante (HVt-L, EVS Stift an/ab, KVz) wird zusaetzlich gefragt, wie viele Stifte ab dem Beginnwert umgeschaltet werden sollen. Leer/0 = unbegrenzt (Verhalten wie bisher).
  - **PDF Export**: 1-Klick PDF-Erzeugung in A4 quer, alle Spalten passen auf eine Seitenbreite.
  - **Letzte Umschaltung rueckgaengig**: jede Umschaltung sichert vorher die betroffene Spalte (Werte + Strikethrough/Farbe). 1 Undo-Schritt verfuegbar.
- **Workbook-Schutz**: aufgehoben (war ohne bekanntes Passwort blockiert)

## Eingangsdatei

Die XML-Anteile sind bereits in `build/FlexProdSchaltzettel_v2.7.xlsm` gepatcht:
- 5 alte Buttons entfernt, 2 neue platziert ("PDF Export", "Letzte Umschaltung rueckgaengig")
- Zurue-Button Beschriftung aktualisiert ("Zurue ein/aus")
- Workbook-Schutz raus
- Changelog-Eintrag v2.7 ergaenzt

Die VBA muss einmalig neu eingespielt werden, da der Linux-Build die binaere `vbaProject.bin` nicht zuverlaessig modifizieren kann.

## VBA-Import (5 Min in Excel)

1. **Datei oeffnen**: `build/FlexProdSchaltzettel_v2.7.xlsm` in Excel oeffnen, Makros aktivieren.
2. **VBA-Editor oeffnen**: Alt+F11
3. **Module loeschen** (Rechtsklick im Projekt-Explorer auf jedes Modul -> "Modul loeschen ohne zu exportieren"):
   - `Modul2` (Schaltzettel_Minimieren)
   - `LeerzeilenCheck`
   - `frmSortieren` (UserForm fuer den Sortier-Dialog)
   - `frmUmschaltung` (alte UserForm wird durch InputBox-Dialog ersetzt)
   - `frmZurueLtg` (alte UserForm fuer Zurue-Loesch-Dialog)
4. **`Tabelle1` Code ersetzen**:
   - Doppelklick auf `Tabelle1` im Projekt-Explorer
   - Gesamten vorhandenen Code markieren (Strg+A) und loeschen
   - Inhalt von `vba/Tabelle1_replace.cls` einfuegen, aber **OHNE** die ersten 12 Zeilen (`VERSION 1.0 CLASS` bis `Attribute VB_Customizable = True` - die werden von Excel automatisch verwaltet)
5. **`Modul1` Code ersetzen**:
   - Doppelklick auf `Modul1`
   - Inhalt loeschen, durch `vba/Modul1_replace.bas` ersetzen (ohne `Attribute VB_Name`-Zeile am Anfang)
6. **`Modul3` Code ersetzen**:
   - Doppelklick auf `Modul3`
   - Inhalt loeschen, durch `vba/Modul3_replace.bas` ersetzen (ohne `Attribute VB_Name`-Zeile)
7. **Neue Module importieren**: Datei -> Datei importieren...
   - `vba/Modul_Umschaltung.bas`
   - `vba/Modul_UmschaltungDialog.bas`
   - `vba/Modul_Export.bas`
8. **Speichern**: Strg+S, beim Format-Dialog "Excel Macro-Enabled Workbook (*.xlsm)" bestaetigen.

## Funktion testen

1. **CSV Import**: wie bisher - Button "CSV Import" druecken, FlexProd-CSV auswaehlen.
2. **Umschaltung**: Button "Umschaltung" druecken. Es oeffnet sich ein Auswahl-Dialog (1=HVt-L, 2=EVS Stift an, 3=EVS Stift ab, 4=KVz). Anschliessend werden alle Werte einzeln per InputBox abgefragt - inklusive **Anzahl Stifte** (leer/0 = unbegrenzt).
3. **Letzte Umschaltung rueckgaengig**: Button druecken, Bestaetigung, Werte + Formate werden auf den Stand vor der letzten Umschaltung zurueckgesetzt.
4. **Zurue ein/aus**: 1. Klick blendet alle Zurue-Leitungen aus, naechster Klick blendet sie wieder ein.
5. **PDF Export**: Button druecken, Speicherort waehlen, fertig - A4 quer, eine Seite breit.

## Anzahl-Stifte-Logik

Bei jedem InputBox "Anzahl Stifte umschalten":
- **leer** oder **0** -> alle passenden Stifte werden umgeschaltet (Verhalten v2.6)
- **5** -> nur die ersten 5 Treffer ab Beginnwert werden umgeschaltet
- nicht-numerische Eingabe -> Abbruch mit Fehlermeldung

Die Strikethrough-Markierung der alten Werte und die rote Hervorhebung der neuen Werte funktioniert wie in v2.6.

## Undo-Buffer

Der Undo-Mechanismus speichert die letzte Umschaltung in einem versteckten Sheet `_UndoBuffer`. Beim naechsten Umschalten wird der Buffer ueberschrieben (Single-Level-Undo). Nach erfolgreichem Undo ist der Buffer leer.

`_UndoBuffer` ist mit `xlSheetVeryHidden` markiert - wird in der Reiter-Liste nicht angezeigt und kann nur via VBA-Editor sichtbar gemacht werden.

## Bekannte Einschraenkungen

- **InputBox statt Userform**: das alte Tab-Dialog (frmUmschaltung) wurde durch eine InputBox-Sequenz ersetzt. Funktional identisch, optisch schlichter. Kann spaeter durch eine neue UserForm ersetzt werden, falls gewuenscht.
- **Anleitung-Sheet** wurde nicht angepasst. Die Hinweise zu Sortierung und Leerzeile sind nicht mehr aktuell und koennen geloescht werden.
- **Implizite Sortierung beim CSV-Import** bleibt aktiv (gemaess deiner Anweisung).
