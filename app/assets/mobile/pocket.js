// opsimath pocket — offline shop-lookup PWA client (docs/MOBILE.md).
// Downloads the snapshot.sqlite3, keeps it in IndexedDB, queries it with
// sql.js. No framework.
(() => {
  "use strict";
  const cfg = window.__pocket || {};
  const els = {
    status: document.getElementById("status"),
    q: document.getElementById("q"),
    scan: document.getElementById("scan"),
    results: document.getElementById("results"),
    empty: document.getElementById("empty"),
    form: document.getElementById("search"),
    scanner: document.getElementById("scanner"),
    cam: document.getElementById("cam"),
    scanhint: document.getElementById("scanhint"),
    scanclose: document.getElementById("scanclose"),
  };

  // --- tiny IndexedDB key/value store -------------------------------------
  const idb = {
    open() {
      return new Promise((resolve, reject) => {
        const r = indexedDB.open("pocket", 1);
        r.onupgradeneeded = () => r.result.createObjectStore("kv");
        r.onsuccess = () => resolve(r.result);
        r.onerror = () => reject(r.error);
      });
    },
    async get(key) {
      const db = await this.open();
      return new Promise((resolve, reject) => {
        const t = db.transaction("kv").objectStore("kv").get(key);
        t.onsuccess = () => resolve(t.result);
        t.onerror = () => reject(t.error);
      });
    },
    async set(key, value) {
      const db = await this.open();
      return new Promise((resolve, reject) => {
        const t = db.transaction("kv", "readwrite").objectStore("kv").put(value, key);
        t.onsuccess = () => resolve();
        t.onerror = () => reject(t.error);
      });
    },
  };

  const norm = (s) =>
    (s || "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().trim();

  const esc = (s) =>
    String(s == null ? "" : s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));

  const setStatus = (text, cls = "") => {
    els.status.textContent = text;
    els.status.className = "status" + (cls ? " " + cls : "");
  };

  const needsRelink = () => {
    els.status.className = "status error";
    els.status.innerHTML = 'session expired — <a href="' + esc(cfg.resetUrl || "") + '">re-link</a>';
  };

  const ago = (iso) => {
    if (!iso) return "never";
    const s = Math.round((Date.now() - new Date(iso)) / 1000);
    if (s < 90) return "just now";
    if (s < 5400) return Math.round(s / 60) + " min ago";
    if (s < 129600) return Math.round(s / 3600) + " h ago";
    return Math.round(s / 86400) + " d ago";
  };

  let SQL = null;
  let db = null;
  let generatedAt = null;

  async function openDb(bytes) {
    if (db) db.close();
    db = new SQL.Database(new Uint8Array(bytes));
  }

  // --- sync -------------------------------------------------------------
  async function token() {
    return (await idb.get("apiToken")) || cfg.apiToken;
  }

  async function sync({ force = false } = {}) {
    if (!navigator.onLine) {
      setStatus(`offline · snapshot ${ago(generatedAt)}`);
      return;
    }
    const auth = { Authorization: "Bearer " + (await token()) };
    try {
      setStatus("checking…", "busy");
      const vres = await fetch(cfg.versionUrl, { headers: auth, cache: "no-store" });
      if (vres.status === 401) return needsRelink();
      if (vres.status === 404) return setStatus("no snapshot published yet", "error");
      if (!vres.ok) throw new Error("version " + vres.status);
      const meta = await vres.json();
      const localVersion = await idb.get("version");

      if (!force && db && localVersion === meta.version) {
        setStatus(`synced · updated ${ago(generatedAt)}`);
        return;
      }

      setStatus("downloading…", "busy");
      const sres = await fetch(cfg.snapshotUrl, { headers: auth, cache: "no-store" });
      if (!sres.ok) throw new Error("snapshot " + sres.status);
      const buf = await sres.arrayBuffer();

      await idb.set("snapshot", buf);
      await idb.set("version", meta.version);
      await idb.set("generatedAt", meta.generated_at);
      generatedAt = meta.generated_at;
      await openDb(buf);
      setStatus(`synced · updated ${ago(generatedAt)}`);
      runSearch();
    } catch (e) {
      console.error(e);
      setStatus(db ? `offline · snapshot ${ago(generatedAt)}` : "sync failed — retry when online", "error");
    }
  }

  // --- queries -------------------------------------------------------
  function editionsOf(entryId) {
    const es = db.prepare("SELECT id, format, format_detail, publisher, year, thumb FROM editions WHERE entry_id = ?");
    es.bind([entryId]);
    const out = [];
    while (es.step()) out.push(es.getAsObject());
    es.free();
    return out;
  }

  function search(query) {
    const terms = norm(query).split(/\s+/).filter(Boolean);
    if (!db || terms.length === 0) return [];

    const where = terms
      .map(() => "(search_title LIKE ? OR search_author LIKE ? OR search_series LIKE ?)")
      .join(" AND ");
    const binds = terms.flatMap((t) => ["%" + t + "%", "%" + t + "%", "%" + t + "%"]);

    const stmt = db.prepare(
      `SELECT id, kind, title, subtitle, authors, series, series_position, year, owned, wishlisted, thumb
       FROM entries WHERE ${where} ORDER BY title LIMIT 40`
    );
    stmt.bind(binds);
    const rows = [];
    while (stmt.step()) rows.push(stmt.getAsObject());
    stmt.free();

    for (const row of rows) if (row.kind === "work") row.editions = editionsOf(row.id);
    return rows;
  }

  function byIsbn(ean) {
    const stmt = db.prepare(
      `SELECT e.id, e.kind, e.title, e.authors, e.series, e.series_position, e.year,
              e.owned, e.wishlisted, e.thumb, i.edition_id AS matched
       FROM isbn_index i JOIN entries e ON e.id = i.entry_id WHERE i.isbn13 = ? LIMIT 1`
    );
    stmt.bind([ean]);
    const row = stmt.step() ? stmt.getAsObject() : null;
    stmt.free();
    if (row && row.kind === "work") row.editions = editionsOf(row.id);
    return row;
  }

  // --- render -------------------------------------------------------
  const blobUrl = (bytes) =>
    bytes && bytes.length ? URL.createObjectURL(new Blob([bytes], { type: "image/webp" })) : null;

  function cardHtml(row) {
    const eds = row.editions || [];
    const thumb = blobUrl((eds.find((e) => e.thumb) || {}).thumb || row.thumb);
    const fmt = (e) => [e.format_detail || e.format, e.publisher, e.year].filter(Boolean).join(" · ");
    const pill = row.owned ? ["owned", "OWNED"] : ["wish", "WISHLIST"];

    return `
      ${thumb ? `<img src="${thumb}" alt="">` : `<div class="noimg">?</div>`}
      <div class="body">
        <div class="title">${esc(row.title)}${row.series ? ` <span class="meta">— ${esc(row.series)}${row.series_position ? " #" + esc(row.series_position) : ""}</span>` : ""}</div>
        <div class="meta">${esc(row.authors || "")}${row.year ? " · " + row.year : ""}</div>
        <span class="pill ${pill[0]}">${pill[1]}</span>
        ${eds.length ? `<div class="editions">${eds.map((e) => `<div class="${row.matched && e.id === row.matched ? "matched" : ""}">${esc(fmt(e))}${row.matched && e.id === row.matched ? " · scanned" : ""}</div>`).join("")}</div>` : ""}
      </div>`;
  }

  function el(cls, html) {
    const d = document.createElement("div");
    d.className = cls;
    d.innerHTML = html;
    return d;
  }

  function clearResults() {
    els.results.querySelectorAll("img[src^=blob]").forEach((i) => URL.revokeObjectURL(i.src));
    els.results.innerHTML = "";
  }

  function render(rows) {
    clearResults();
    els.empty.hidden = rows.length > 0 || norm(els.q.value) === "";
    for (const row of rows) els.results.appendChild(el("card", cardHtml(row)));
  }

  function renderScan(ean, row) {
    clearResults();
    els.empty.hidden = true;
    els.q.value = "";
    if (row) {
      els.results.appendChild(el("card", cardHtml(row)));
    } else {
      els.results.appendChild(el("card neither", `
        <div class="noimg">✕</div>
        <div class="body">
          <div class="title">Not in your collection</div>
          <div class="meta">${esc(ean)} — not owned, not on your wishlist</div>
          <span class="pill neither">NEITHER</span>
        </div>`));
    }
  }

  let searchTimer = null;
  function runSearch() {
    clearTimeout(searchTimer);
    searchTimer = setTimeout(() => render(search(els.q.value)), 120);
  }

  // --- barcode scanner --------------------------------------------
  let detector = null;
  let stream = null;
  let scanPoll = null;
  let scanBusy = false;

  async function openScanner() {
    if (!db) return setStatus("no snapshot yet — connect once first", "error");
    try {
      detector = detector || new window.BarcodeDetector({ formats: ["ean_13"] });
      stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: "environment" } });
      els.cam.srcObject = stream;
      await els.cam.play();
      els.scanner.hidden = false;
      els.scanhint.textContent = "point at the barcode";
      scanPoll = setInterval(pollBarcode, 250);
    } catch (e) {
      console.error(e);
      closeScanner();
      setStatus(e && e.name === "NotAllowedError" ? "camera permission denied" : "camera unavailable", "error");
    }
  }

  async function pollBarcode() {
    if (scanBusy || els.scanner.hidden || !els.cam.videoWidth) return;
    scanBusy = true;
    try {
      const codes = await detector.detect(els.cam);
      const ean = codes.map((c) => c.rawValue).find((v) => /^\d{13}$/.test(v));
      if (ean) {
        closeScanner();
        renderScan(ean, byIsbn(ean));
      }
    } catch (_) { /* transient decode errors are normal */ }
    finally { scanBusy = false; }
  }

  function closeScanner() {
    els.scanner.hidden = true;
    clearInterval(scanPoll);
    if (stream) stream.getTracks().forEach((t) => t.stop());
    stream = null;
  }

  // --- boot ----------------------------------------------------------
  async function boot() {
    if ("serviceWorker" in navigator && cfg.serviceWorkerUrl) {
      navigator.serviceWorker.register(cfg.serviceWorkerUrl, { scope: cfg.scope }).catch(console.error);
    }
    if (cfg.apiToken) await idb.set("apiToken", cfg.apiToken);

    setStatus("loading…", "busy");
    SQL = await initSqlJs({ locateFile: () => cfg.sqljsWasmUrl });

    const [bytes, ga] = await Promise.all([idb.get("snapshot"), idb.get("generatedAt")]);
    generatedAt = ga || null;
    if (bytes) {
      await openDb(bytes);
      setStatus(`snapshot ${ago(generatedAt)} · checking…`, "busy");
    }

    els.q.addEventListener("input", runSearch);
    els.form.addEventListener("submit", (e) => { e.preventDefault(); runSearch(); });
    els.status.addEventListener("click", () => sync({ force: true }));
    window.addEventListener("online", () => sync());

    if ("BarcodeDetector" in window && navigator.mediaDevices) {
      els.scan.hidden = false;
      els.scan.addEventListener("click", openScanner);
      els.scanclose.addEventListener("click", closeScanner);
    }

    await sync();
  }

  boot().catch((e) => { console.error(e); setStatus("failed to start", "error"); });
})();
