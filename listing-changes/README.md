# Listing Changes Timeline

Visualisiert den Tab **Changes** des ASIN-Tracker-Sheets als zwei Zeitleisten
(eigene ASINs oben, Wettbewerber unten) mit Vorher/Nachher-Panel.

## Dateien

| Datei | Zweck |
|---|---|
| `index.html` | Seite für Hosting (GitHub Pages), lädt `data.json` und `asins.json` per fetch |
| `app.js` | Gesamte Logik: Filter, Swimlanes, Brush-Zoom, Detail-Panel, Listenansicht |
| `style.css` | Tokens für Hell/Dunkel, Layout |
| `data.json` | Snapshot des Changes-Tabs (`exportedAt` = Datenstand) |
| `asins.json` | Reihenfolge, Kurzlabel und Wettbewerber-Zuordnung (aus Tab ASINs) |
| `build.py` | Bündelt alles in `index-standalone.html` und `artifact.html` |

## Daten aktualisieren

1. Changes-Tab (Spalten A–I) nach `data.json` exportieren, Struktur:
   `{"exportedAt": "YYYY-MM-DD", "changes": [{date, asin, product, field, old, new, compOf, compOfProduct, marketplace}]}`
2. Neue ASINs oder Wettbewerber in `asins.json` ergänzen (unbekannte ASINs
   aus den Daten werden automatisch angehängt, nur ohne schönes Label).
3. `python3 build.py` ausführen, dann `artifact.html` neu veröffentlichen.

## Kategorien

| Kategorie | Felder |
|---|---|
| Preis | price |
| Bilder | main_image, image_1 … image_6 |
| Text | title, bullet_1 … bullet_5, description |
| Verfügbarkeit | fulfillment, offer_count |
| Sonstiges | alles andere (z. B. brand) |

## Varianten direkt in Google Sheets

Im ASIN-Tracker-Sheet gibt es zwei zusätzliche Tabs, die ohne externe Seite auskommen:

- **Changes_Viz**: ARRAYFORMULA-Hilfstabelle über dem Changes-Tab (Datum, Zeile je ASIN,
  Kategorie, je eine Spalte pro Kategorie und Lane). Rechts ab Spalte Z liegen zwei
  Scatter-Diagramme (eigene ASINs / Wettbewerber), Y-Achse = Zeile aus den Schlüsseltabellen
  Q:S bzw. U:X. Zeile 2 ist eine technische Ankerzeile, damit alle fünf Serien im Chart
  erhalten bleiben (die Sheets-API verwirft leere Serien).
- **Changes_Detail**: ASIN und Datum per Dropdown, darunter alle Änderungen des Tages mit
  Vorher/Nachher, Bild-Thumbnails über IMAGE() und Preis-Delta.

Die Sheet-Locale ist de_DE: Formeln nutzen `;` als Trenner und `\` in Array-Literalen.

## Apps-Script-Variante (volle Timeline im Sheet)

`apps-script/Code.gs` und `apps-script/Index.html` liefern die komplette Timeline als
Dialog im Sheet (Menü „ASIN-Tracker → Changes Timeline“) oder als Web-App. Daten kommen
live aus den Tabs Changes und ASINs. Einrichtung steht im Kopf von `Code.gs`.
