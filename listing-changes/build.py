#!/usr/bin/env python3
"""Bundle style.css, app.js, data.json and asins.json into single-file outputs.

  index-standalone.html  full HTML document, open locally or host anywhere
  artifact.html          fragment without <html>/<head>/<body>, for the Claude artifact publisher
"""
import json
import pathlib

HERE = pathlib.Path(__file__).parent
css = (HERE / "style.css").read_text(encoding="utf-8")
js = (HERE / "app.js").read_text(encoding="utf-8")
data = json.loads((HERE / "data.json").read_text(encoding="utf-8"))
asins = json.loads((HERE / "asins.json").read_text(encoding="utf-8"))

FONT = '<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:wght@400;500;600;700&family=IBM+Plex+Mono:wght@400;500&display=swap">'


def payload():
    return (json.dumps(data, ensure_ascii=False).replace("</", "<\\/"),
            json.dumps(asins, ensure_ascii=False).replace("</", "<\\/"))


d, a = payload()
core = f"""{FONT}
<style>
{css}
</style>
<div class="app" id="app"></div>
<script>
{js}
</script>
<script>
ListingChanges.init(document.getElementById('app'), {d}, {a});
</script>
"""

(HERE / "artifact.html").write_text(f"<title>Listing Changes Timeline</title>\n{core}", encoding="utf-8")
(HERE / "index-standalone.html").write_text(
    "<!DOCTYPE html>\n<html lang=\"de\">\n<head>\n<meta charset=\"UTF-8\">\n"
    "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n"
    "<title>Listing Changes Timeline</title>\n</head>\n<body>\n" + core + "</body>\n</html>\n",
    encoding="utf-8",
)
print("wrote artifact.html and index-standalone.html,", len(data["changes"]), "changes")
