# Wetter-/Regenradar-Daten für Entwickler – Recherche

## Hauptquellen

### 1. DWD Open Data (Deutscher Wetterdienst) – Kostenlos
- **URL:** https://opendata.dwd.de/weather/radar/
- **Lizenz:** GeoNutzV / CC BY 4.0 – kostenlos, auch kommerziell, nur Quellenangabe nötig
- **Radar-Produkte:** RADOLAN (kalibriert, 5-min), RADVOR (2h-Vorhersage), Composit
- **Formate:** HDF5, Binary (RADOLAN), GeoTIFF
- **Update:** Alle 5 Minuten
- **Parser:** Python (wradlib), Go (jonnyschaefer/radolan), Java (BITPlan/com.bitplan.radolan), R (rdwd)

### 2. Bright Sky API – Kostenlos
- **URL:** https://brightsky.dev/
- JSON REST API über DWD-Daten inkl. Radar (RADOLAN), Warnungen
- Open Source (MIT), kein API-Key nötig
- Self-Hosting möglich

### 3. Open-Meteo API – Kostenlos (nicht-kommerziell)
- **URL:** https://open-meteo.com/
- JSON REST API, kein API-Key nötig (Free Tier: 10.000 Calls/Tag)
- Nutzt DWD ICON, NOAA GFS, ECMWF u.a.
- Kommerziell ab ~$15/Monat

### 4. RainViewer API – Freemium
- **URL:** https://www.rainviewer.com/api.html
- Radar-Tiles (PNG) für Leaflet/Google Maps
- Free: 1.000 Calls/Tag, Zoom max 7, nur Vergangenheit (~2h)
- Bezahlt: Nowcast/Forecast, höhere Auflösung

### 5. Apple WeatherKit – Kostenpflichtig
- **URL:** https://developer.apple.com/weatherkit/
- 500.000 Calls/Monat inkl. (bei $99/Jahr Apple Developer Program)
- Minute-by-Minute Niederschlagsvorhersage
- JWT-Auth, REST + Swift

### 6. OpenWeatherMap – Freemium
- **URL:** https://openweathermap.org/api
- Free: 1.000 Calls/Tag, Basis-Tiles
- Hochauflösendes Radar ab $180/Monat

### 7. Morgenwirdes.de API – Kostenlos
- **URL:** https://morgenwirdes.de/api/
- Regenvorhersage (2h) als Text/JSON per PLZ/Koordinaten

### 8. DWD API (Bund)
- **URL:** https://dwd.api.bund.dev/
- Community-Wrapper: https://github.com/bundesAPI/dwd-api

## Was nutzen die großen Apps?
| App | Datenquelle |
|-----|-------------|
| Regenradar (WetterOnline) | DWD-Radardaten + eigene Verarbeitung |
| Apple Wetter | WeatherKit (DWD, NOAA, ECMWF, Met Office u.a.) |
| Warnwetter (DWD) | DWD eigene Daten |

## Empfehlung
- **Einfachster Einstieg:** Bright Sky oder Open-Meteo
- **Radar-Karten:** RainViewer (fertige Tiles) oder DWD direkt
- **Maximale Kontrolle:** DWD Open Data (Rohdaten + Parser)
