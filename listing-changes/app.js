/* Listing Changes Timeline
 * Two swimlane timelines (own ASINs / competitor ASINs) over the "Changes" tab
 * of the ASIN tracker sheet, with a before/after detail panel.
 * No dependencies. Data arrives via ListingChanges.init(root, data, asins).
 */
const ListingChanges = (() => {
  const IMG = ["main_image", "image_1", "image_2", "image_3", "image_4", "image_5", "image_6"];
  const TXT = ["title", "bullet_1", "bullet_2", "bullet_3", "bullet_4", "bullet_5", "description"];
  const CATS = [
    ["price", "Preis"], ["image", "Bilder"], ["text", "Text"], ["avail", "Verfügbarkeit"], ["other", "Sonstiges"],
  ];
  const COL = { price: "var(--c-price)", image: "var(--c-image)", text: "var(--c-text)", avail: "var(--c-avail)", other: "var(--c-other)" };
  const CAT_LABEL = Object.fromEntries(CATS);
  const DAY = 864e5;

  const cat = f => f === "price" ? "price" : IMG.includes(f) ? "image" : TXT.includes(f) ? "text"
    : (f === "fulfillment" || f === "offer_count") ? "avail" : "other";
  const esc = s => String(s ?? "").replace(/[&<>"]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
  const pd = s => new Date(s + "T00:00:00");
  const fmtD = d => d.toLocaleDateString("de-DE", { day: "2-digit", month: "2-digit", year: "numeric" });
  const fmtDs = d => d.toLocaleDateString("de-DE", { day: "2-digit", month: "2-digit" });
  const fmtEur = v => (v === "" || v == null || isNaN(+v)) ? "—" : (Math.round(+v * 100) / 100).toFixed(2).replace(".", ",") + " €";

  let root, DATA, LANES_OWN, LANES_COMP, NAME, TITLE, COMPOF, TODAY, MIN, MARKETS;
  const state = { days: 0, range: null, cats: new Set(CATS.map(c => c[0])), asin: "", mp: "", q: "", view: "timeline", sel: null };

  // ---------- data prep ----------
  function prepare(data, asins) {
    const rows = data.changes.map(r => ({ ...r, c: cat(r.field), t: pd(r.date) }));
    NAME = {}; TITLE = {}; COMPOF = {};
    const own = [], comp = [];
    (asins.own || []).forEach(o => { own.push(o.asin); NAME[o.asin] = o.label || short(o.title); TITLE[o.asin] = o.title || ""; });
    (asins.competitors || []).forEach(c => { comp.push(c.asin); COMPOF[c.asin] = c.compOf; NAME[c.asin] = c.label || short(c.title); TITLE[c.asin] = c.title || ""; });
    rows.forEach(r => {
      if (r.compOf) {
        if (!COMPOF[r.asin]) { COMPOF[r.asin] = r.compOf; comp.push(r.asin); }
        if (!NAME[r.compOf]) { NAME[r.compOf] = short(r.compOfProduct); TITLE[r.compOf] = r.compOfProduct; own.push(r.compOf); }
      } else if (!own.includes(r.asin)) { own.push(r.asin); }
      if (!NAME[r.asin]) { NAME[r.asin] = short(r.product); TITLE[r.asin] = r.product; }
      if (!TITLE[r.asin]) TITLE[r.asin] = r.product;
    });
    LANES_OWN = own.map(a => ({ a, own: true }));
    LANES_COMP = comp.slice().sort((x, y) => own.indexOf(COMPOF[x]) - own.indexOf(COMPOF[y]))
      .map(a => ({ a, own: false }));
    let k = {}; LANES_COMP.forEach(l => { const p = COMPOF[l.a]; k[p] = (k[p] || 0) + 1; l.k = k[p]; });
    const dates = rows.map(r => r.t.getTime());
    MIN = new Date(Math.min(...dates) - 3 * DAY);
    const exp = data.exportedAt ? pd(data.exportedAt) : new Date(Math.max(...dates));
    TODAY = exp;
    MARKETS = [...new Set(rows.map(r => r.marketplace).filter(Boolean))];
    DATA = rows;
  }
  const short = t => (t || "").replace(/\s+[–|-].*$/, "").slice(0, 32);

  // ---------- filtering ----------
  function domain() {
    if (state.range) return [state.range[0], state.range[1]];
    const s = state.days ? new Date(TODAY.getTime() - state.days * DAY) : MIN;
    return [s, new Date(TODAY.getTime() + 2 * DAY)];
  }
  function laneMatches(a) {
    if (state.mp && !DATA.some(r => r.asin === a && (r.marketplace || "") === state.mp)) return false;
    if (state.q) {
      const q = state.q.toLowerCase();
      return a.toLowerCase().includes(q) || (NAME[a] || "").toLowerCase().includes(q) || (TITLE[a] || "").toLowerCase().includes(q);
    }
    return true;
  }
  function inFocus(a) {
    if (!state.asin) return true;
    return a === state.asin || COMPOF[a] === state.asin;
  }
  function visibleRows() {
    const [d0, d1] = domain();
    return DATA.filter(r => r.t >= d0 && r.t <= d1 && state.cats.has(r.c)
      && (!state.mp || (r.marketplace || "") === state.mp) && laneMatches(r.asin) && inFocus(r.asin));
  }
  function groups(rows) {
    const m = new Map();
    rows.forEach(r => { const k = r.asin + "|" + r.date; if (!m.has(k)) m.set(k, { a: r.asin, d: r.date, t: r.t, evs: [] }); m.get(k).evs.push(r); });
    return [...m.values()];
  }

  // ---------- shell ----------
  function shell() {
    root.innerHTML = `
      <div class="head">
        <h1>Listing Changes</h1>
        <span class="stand">Stand <b id="stand"></b> · <b id="total"></b> Änderungen · Quelle: ASIN-Tracker › Changes</span>
      </div>
      <div class="bar">
        <span class="seg" id="range">
          <button data-d="30">30 Tage</button><button data-d="90">90 Tage</button><button data-d="0" class="on">Alles</button>
        </span>
        <span id="zoom" class="hint" hidden></span>
        <span id="cats"></span>
        <select id="asinsel" class="sel"><option value="">Alle eigenen ASINs</option></select>
        <select id="mpsel" class="sel" hidden><option value="">Alle Märkte</option></select>
        <input id="q" class="search" type="search" placeholder="ASIN oder Produkt suchen">
        <span class="grow"></span>
        <span class="seg" id="view"><button data-v="timeline" class="on">Zeitleiste</button><button data-v="list">Liste</button></span>
      </div>
      <div class="body">
        <div id="left"></div>
        <div class="detail" id="detail"></div>
      </div>
      <div class="legend" id="legend"></div>`;
    root.querySelector("#stand").textContent = fmtD(TODAY);
    root.querySelector("#total").textContent = DATA.length;
    const catsEl = root.querySelector("#cats");
    CATS.forEach(([k, l]) => {
      const b = document.createElement("button"); b.className = "chip on"; b.type = "button";
      b.innerHTML = `<span class="sw" style="background:${COL[k]}"></span>${l}`;
      b.onclick = () => { state.cats.has(k) ? state.cats.delete(k) : state.cats.add(k); b.classList.toggle("on"); b.classList.toggle("off"); render(); };
      catsEl.appendChild(b);
    });
    root.querySelectorAll("#range button").forEach(b => b.onclick = () => {
      root.querySelectorAll("#range button").forEach(x => x.classList.remove("on")); b.classList.add("on");
      state.days = +b.dataset.d; state.range = null; render();
    });
    root.querySelectorAll("#view button").forEach(b => b.onclick = () => {
      root.querySelectorAll("#view button").forEach(x => x.classList.remove("on")); b.classList.add("on");
      state.view = b.dataset.v; render();
    });
    const sel = root.querySelector("#asinsel");
    LANES_OWN.forEach(l => { const o = document.createElement("option"); o.value = l.a; o.textContent = `${NAME[l.a]} · ${l.a}`; sel.appendChild(o); });
    sel.onchange = () => { state.asin = sel.value; render(); };
    const mp = root.querySelector("#mpsel");
    if (MARKETS.length > 1) { mp.hidden = false; MARKETS.forEach(m => { const o = document.createElement("option"); o.value = m; o.textContent = m; mp.appendChild(o); }); mp.onchange = () => { state.mp = mp.value; render(); }; }
    const q = root.querySelector("#q"); q.oninput = () => { state.q = q.value.trim(); render(); };
    root.querySelector("#legend").innerHTML = `<span>Punkt = Tag mit Änderungen, Zahl = Anzahl. Ring = zweite Kategorie am selben Tag.</span><span>Ziehen auf der Zeitleiste zoomt.</span><span>Gestrichelt = Datenstand.</span>`;
  }

  // ---------- timeline ----------
  function drawLane(svg, lanes, rows, label) {
    const W = Math.max(svg.parentElement.clientWidth || 800, 640), LEFT = 176, RIGHT = 56, RH = 30, TOP = 24;
    const H = TOP + Math.max(lanes.length, 1) * RH + 8;
    svg.setAttribute("viewBox", `0 0 ${W} ${H}`); svg.setAttribute("height", H); svg.setAttribute("width", "100%");
    const [d0, d1] = domain();
    const x = d => LEFT + (d - d0) / (d1 - d0) * (W - LEFT - RIGHT);
    const xInv = px => new Date(d0.getTime() + (px - LEFT) / (W - LEFT - RIGHT) * (d1 - d0));
    let s = "";
    const span = (d1 - d0) / DAY;
    const t = new Date(d0.getFullYear(), d0.getMonth(), 1);
    if (span > 45) {
      while (t < d1) {
        if (t >= d0) { const xx = x(t); s += `<line class="grid" x1="${xx}" y1="${TOP - 4}" x2="${xx}" y2="${H - 6}"/><text class="tick" x="${xx + 4}" y="${TOP - 9}">${t.toLocaleDateString("de-DE", { month: "short", year: "2-digit" })}</text>`; }
        t.setMonth(t.getMonth() + 1);
      }
    } else {
      const step = span > 14 ? 7 : span > 5 ? 2 : 1;
      const start = new Date(Math.ceil(d0.getTime() / DAY) * DAY);
      for (let d = start; d < d1; d = new Date(d.getTime() + step * DAY)) {
        const xx = x(d); s += `<line class="grid" x1="${xx}" y1="${TOP - 4}" x2="${xx}" y2="${H - 6}"/><text class="tick" x="${xx + 3}" y="${TOP - 9}">${fmtDs(d)}</text>`;
      }
    }
    if (TODAY >= d0 && TODAY <= d1) { const xt = x(TODAY); s += `<line class="today" x1="${xt}" y1="${TOP - 4}" x2="${xt}" y2="${H - 6}"/>`; }
    if (!lanes.length) s += `<text class="empty" x="${LEFT}" y="${TOP + 18}">Keine ${label} im Filter.</text>`;
    const gs = groups(rows);
    lanes.forEach((ln, i) => {
      const y = TOP + i * RH + RH / 2;
      const dim = !inFocus(ln.a) || !laneMatches(ln.a);
      s += `<g class="${dim ? "dim" : ""}"><line class="row" x1="${LEFT}" y1="${y}" x2="${W - RIGHT}" y2="${y}"/>`;
      s += ln.own
        ? `<rect class="own-badge" x="10" y="${y - 7}" width="18" height="14" rx="3"/><text class="own-badge-t" x="13" y="${y + 3.5}">ME</text>`
        : `<rect class="comp-badge" x="10" y="${y - 7}" width="18" height="14" rx="3"/><text class="comp-badge-t" x="13.5" y="${y + 3.5}">K${ln.k}</text>`;
      const nm = NAME[ln.a] || ln.a;
      const sub = ln.own ? ln.a : `${ln.a} · zu ${NAME[COMPOF[ln.a]] || COMPOF[ln.a]}`;
      s += `<text class="lbl" x="34" y="${y - 2}"><title>${esc(TITLE[ln.a])}</title>${esc(nm.length > 24 ? nm.slice(0, 23) + "…" : nm)}</text><text class="asin" x="34" y="${y + 10}">${esc(sub.length > 30 ? sub.slice(0, 29) + "…" : sub)}</text>`;
      if (dim) { s += "</g>"; return; }
      gs.filter(g => g.a === ln.a).forEach(g => {
        const evs = g.evs; const n = evs.length; const r = n > 1 ? 8 : 5.5;
        const counts = {}; evs.forEach(e => counts[e.c] = (counts[e.c] || 0) + 1);
        const order = Object.keys(counts).sort((a, b) => counts[b] - counts[a]);
        const isSel = state.sel && state.sel.a === g.a && state.sel.d === g.d;
        const tip = `${fmtD(g.t)} · ${NAME[g.a]} · ${n} Änderung${n > 1 ? "en" : ""}: ${order.map(c => `${CAT_LABEL[c]} ${counts[c]}`).join(", ")}`;
        if (order.length > 1) s += `<circle class="ring" cx="${x(g.t)}" cy="${y}" r="${r + 3.5}" stroke="${COL[order[1]]}"/>`;
        s += `<circle class="ev ${isSel ? "sel" : ""}" tabindex="0" role="button" data-a="${g.a}" data-d="${g.d}" cx="${x(g.t)}" cy="${y}" r="${r}" fill="${COL[order[0]]}"><title>${esc(tip)}</title></circle>`;
        if (n > 1) s += `<text class="cnt ${order[0] === "avail" ? "dark" : ""}" x="${x(g.t)}" y="${y + 3.3}" text-anchor="middle">${n}</text>`;
      });
      s += "</g>";
    });
    s += `<rect class="brush" id="brush" x="0" y="${TOP - 4}" width="0" height="${H - TOP - 2}" hidden/>`;
    svg.innerHTML = s;
    svg.querySelectorAll(".ev").forEach(c => {
      const pick = () => { state.sel = { a: c.dataset.a, d: c.dataset.d }; render(); };
      c.addEventListener("click", e => { e.stopPropagation(); pick(); });
      c.addEventListener("keydown", e => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); pick(); } });
    });
    // brush to zoom
    let x0 = null; const br = svg.querySelector("#brush");
    const px = e => { const r = svg.getBoundingClientRect(); return (e.clientX - r.left) * (W / r.width); };
    svg.addEventListener("pointerdown", e => { if (e.target.classList.contains("ev")) return; x0 = Math.min(Math.max(px(e), LEFT), W - RIGHT); svg.setPointerCapture(e.pointerId); svg.parentElement.classList.add("brushing"); });
    svg.addEventListener("pointermove", e => { if (x0 == null) return; const x1 = Math.min(Math.max(px(e), LEFT), W - RIGHT); br.hidden = false; br.setAttribute("x", Math.min(x0, x1)); br.setAttribute("width", Math.abs(x1 - x0)); });
    svg.addEventListener("pointerup", e => {
      if (x0 == null) return; const x1 = Math.min(Math.max(px(e), LEFT), W - RIGHT); svg.parentElement.classList.remove("brushing");
      const a = Math.min(x0, x1), b = Math.max(x0, x1); x0 = null; br.hidden = true;
      if (b - a < 8) return;
      let from = xInv(a), to = xInv(b); if (to - from < 3 * DAY) to = new Date(from.getTime() + 3 * DAY);
      state.range = [from, to]; render();
    });
  }
  function renderTimeline(left) {
    left.innerHTML = `<div class="lanes"><div class="lane-h"><b>Meine ASINs</b><span class="n" id="ownN"></span></div><svg id="laneOwn"></svg>
      <div class="lane-h"><b>Wettbewerber</b><span class="n" id="compN"></span></div><svg id="laneComp"></svg></div>`;
    const vis = visibleRows();
    const ownRows = vis.filter(r => !COMPOF[r.asin]), compRows = vis.filter(r => COMPOF[r.asin]);
    left.querySelector("#ownN").textContent = `${ownRows.length} Änderungen im Zeitraum`;
    left.querySelector("#compN").textContent = `${compRows.length} Änderungen im Zeitraum`;
    drawLane(left.querySelector("#laneOwn"), LANES_OWN, ownRows, "eigenen ASINs");
    drawLane(left.querySelector("#laneComp"), LANES_COMP, compRows, "Wettbewerber");
  }

  // ---------- list view ----------
  function renderList(left) {
    const vis = visibleRows().slice().sort((a, b) => b.t - a.t || a.asin.localeCompare(b.asin));
    let h = `<div class="table"><table><thead><tr><th>Datum</th><th>ASIN</th><th>Produkt</th><th>Feld</th><th>Vorher</th><th>Nachher</th></tr></thead><tbody>`;
    vis.forEach(r => {
      const own = !COMPOF[r.asin];
      h += `<tr class="rowlink" data-a="${r.asin}" data-d="${r.date}"><td class="mono">${fmtD(r.t)}</td><td class="mono">${r.asin}</td>
        <td>${own ? "" : `<span class="pill">K</span>`}${esc(NAME[r.asin])}</td>
        <td class="mono"><span class="sw" style="background:${COL[r.c]};margin-right:6px;vertical-align:-1px"></span>${r.field}</td>
        <td class="val" title="${esc(r.old)}">${cell(r, r.old)}</td><td class="val" title="${esc(r.new)}">${cell(r, r.new)}</td></tr>`;
    });
    h += `</tbody></table></div>`;
    if (!vis.length) h = `<div class="detail"><div class="empty">Keine Änderungen im Filter.</div></div>`;
    left.innerHTML = h;
    left.querySelectorAll("tr.rowlink").forEach(tr => tr.onclick = () => { state.sel = { a: tr.dataset.a, d: tr.dataset.d }; renderDetail(); });
  }
  const cell = (r, v) => r.c === "price" ? fmtEur(v) : r.c === "image" ? (v ? v.replace(/^.*\/I\//, "") : "—") : (v === "" ? "—" : esc(v));

  // ---------- detail ----------
  function wordDiff(a, b) {
    const A = a.split(/\s+/).filter(Boolean), B = b.split(/\s+/).filter(Boolean), n = A.length, m = B.length;
    if (n * m > 4e6) return `<del>${esc(a)}</del>\n<ins>${esc(b)}</ins>`;
    const L = Array.from({ length: n + 1 }, () => new Uint16Array(m + 1));
    for (let i = n - 1; i >= 0; i--) for (let j = m - 1; j >= 0; j--) L[i][j] = A[i] === B[j] ? L[i + 1][j + 1] + 1 : Math.max(L[i + 1][j], L[i][j + 1]);
    let i = 0, j = 0; const out = [];
    while (i < n && j < m) {
      if (A[i] === B[j]) { out.push(esc(A[i])); i++; j++; }
      else if (L[i + 1][j] >= L[i][j + 1]) { out.push("<del>" + esc(A[i]) + "</del>"); i++; }
      else { out.push("<ins>" + esc(B[j]) + "</ins>"); j++; }
    }
    while (i < n) out.push("<del>" + esc(A[i++]) + "</del>");
    while (j < m) out.push("<ins>" + esc(B[j++]) + "</ins>");
    return out.join(" ");
  }
  function spark(asin, selDate) {
    const pts = DATA.filter(r => r.asin === asin && r.field === "price").map(r => ({ t: r.t, v: r.new === "" ? null : +r.new, d: r.date }));
    if (pts.length < 2) return "";
    const W = 320, H = 64, P = 8, PR = 44;
    const d0 = new Date(pts[0].t.getTime() - 2 * DAY), d1 = new Date(TODAY.getTime() + DAY);
    const xs = d => P + (d - d0) / (d1 - d0) * (W - P - PR);
    const vs = pts.map(p => p.v).filter(v => v != null); const lo = Math.min(...vs), hi = Math.max(...vs);
    const ys = v => H - P - (v - lo) / ((hi - lo) || 1) * (H - 2 * P - 8);
    let path = "", last = null, dots = "";
    pts.forEach(p => {
      const X = xs(p.t);
      if (p.v == null) { last = null; return; }
      const Y = ys(p.v);
      path += last == null ? `M${X},${Y}` : `L${X},${ys(last)} L${X},${Y}`;
      dots += `<circle class="pt ${p.d === selDate ? "sel" : ""}" cx="${X}" cy="${Y}" r="${p.d === selDate ? 3.5 : 2.5}"><title>${fmtD(p.t)} · ${fmtEur(p.v)}</title></circle>`;
      last = p.v;
    });
    if (last != null) path += `L${xs(d1)},${ys(last)}`;
    return `<svg class="spark" viewBox="0 0 ${W} ${H}" width="100%"><line class="g" x1="${P}" y1="${H - P}" x2="${W - PR}" y2="${H - P}"/><path d="${path}"/>${dots}<text x="${W - 2}" y="${P + 4}" text-anchor="end">${fmtEur(hi)}</text><text x="${W - 2}" y="${H - P}" text-anchor="end">${fmtEur(lo)}</text></svg><div class="caption">Preisverlauf dieser ASIN seit ${fmtDs(pts[0].t)} aus dem Log · ${pts.length} Preisänderungen</div>`;
  }
  const availBadge = v => v === "" ? `<span class="badge none">kein Angebot</span>` : /FBA/i.test(v) ? `<span class="badge fba">${esc(v)}</span>` : /FBM/i.test(v) ? `<span class="badge fbm">${esc(v)}</span>` : `<span class="badge">${esc(v)}</span>`;
  function renderDetail() {
    const el = root.querySelector("#detail");
    if (!state.sel) { el.innerHTML = `<div class="empty">Punkt in der Zeitleiste anklicken, um Vorher und Nachher zu sehen.</div>`; return; }
    const { a, d } = state.sel; const evs = DATA.filter(r => r.asin === a && r.date === d);
    if (!evs.length) { el.innerHTML = `<div class="empty">Keine Daten für ${a} am ${d}.</div>`; return; }
    const own = !COMPOF[a]; const t = pd(d);
    const oos = evs.some(e => e.field === "price" && e.new === "") && evs.some(e => e.field === "fulfillment" && e.new === "");
    const back = evs.some(e => e.field === "price" && e.old === "" && e.new !== "") && evs.some(e => e.field === "fulfillment" && e.old === "");
    let h = `<h2 title="${esc(TITLE[a])}">${esc(NAME[a])}</h2><div class="sub"><span>${a}</span><span>${fmtD(t)}</span><a href="https://www.amazon.de/dp/${a}" target="_blank" rel="noopener">auf Amazon öffnen</a></div>`;
    h += own ? `<span class="pill own">Meine ASIN</span>` : `<span class="pill">Wettbewerber</span><span class="pill">zu ${esc(NAME[COMPOF[a]])}</span>`;
    if (oos) h += `<span class="badge none">Out of stock ab diesem Tag</span>`;
    if (back) h += `<span class="badge fba">Wieder verfügbar</span>`;
    h += `<div class="evlist">`;
    evs.forEach(e => {
      const o = e.old ?? "", n = e.new ?? "";
      h += `<div class="ev-card"><div class="fld"><span class="sw" style="background:${COL[e.c]}"></span>${e.field}</div>`;
      if (e.c === "price") {
        h += `<div class="ba"><div class="v big">${fmtEur(o)}</div><div class="arr">→</div><div class="v big">${fmtEur(n)}</div></div>`;
        if (o !== "" && n !== "") { const dl = +n - +o, pc = dl / +o * 100; h += `<div class="delta ${dl > 0 ? "up" : dl < 0 ? "down" : ""}">${dl > 0 ? "+" : ""}${dl.toFixed(2).replace(".", ",")} € (${pc > 0 ? "+" : ""}${pc.toFixed(1).replace(".", ",")} %)</div>`; }
        else if (n === "") h += `<div class="delta">Kein Preis mehr gelistet</div>`; else h += `<div class="delta">Preis neu gelistet</div>`;
        h += spark(a, d);
      } else if (e.c === "image") {
        const im = (u, alt) => u ? `<a href="${esc(u)}" target="_blank" rel="noopener"><img src="${esc(u)}" alt="${alt}" loading="lazy"></a>` : `<div class="none">${alt === "vorher" ? "vorher kein Bild" : "Bild entfernt"}</div>`;
        h += `<div class="imgba">${im(o, "vorher")}<div class="arr">→</div>${im(n, "nachher")}</div>`;
        if (!o && n) h += `<div class="caption">Neu hinzugefügt</div>`;
      } else if (e.c === "text") {
        h += o === n ? `<div class="diff same">${esc(n)}</div>` : `<div class="diff">${wordDiff(o, n)}</div>`;
        const wo = o.split(/\s+/).filter(Boolean).length, wn = n.split(/\s+/).filter(Boolean).length;
        h += `<div class="caption">${o.length} → ${n.length} Zeichen · ${wo} → ${wn} Wörter</div>`;
      } else if (e.field === "fulfillment") {
        h += `<div class="ba"><div>${availBadge(o)}</div><div class="arr">→</div><div>${availBadge(n)}</div></div>`;
      } else if (e.field === "offer_count") {
        h += `<div class="ba"><div class="v">${esc(o) || "0"} Angebote</div><div class="arr">→</div><div class="v">${esc(n) || "0"} Angebote</div></div>`;
      } else {
        h += `<div class="ba"><div class="v">${esc(o) || "—"}</div><div class="arr">→</div><div class="v">${esc(n) || "—"}</div></div>`;
      }
      h += `</div>`;
    });
    h += `</div>`;
    el.innerHTML = h;
  }

  // ---------- render ----------
  function render() {
    const z = root.querySelector("#zoom");
    if (state.range) { z.hidden = false; z.innerHTML = `Zoom ${fmtDs(state.range[0])} – ${fmtDs(state.range[1])} <button class="linkbtn" id="unzoom">zurücksetzen</button>`; z.querySelector("#unzoom").onclick = () => { state.range = null; render(); }; }
    else z.hidden = true;
    const left = root.querySelector("#left");
    state.view === "list" ? renderList(left) : renderTimeline(left);
    renderDetail();
  }

  function init(el, data, asins) {
    root = el; prepare(data, asins || {}); shell();
    // open the most recent own-ASIN change so the page shows what it does
    const last = DATA.filter(r => !COMPOF[r.asin]).sort((a, b) => b.t - a.t)[0];
    if (last) state.sel = { a: last.asin, d: last.date };
    render();
    let raf; window.addEventListener("resize", () => { cancelAnimationFrame(raf); raf = requestAnimationFrame(render); });
  }
  return { init };
})();
