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

  // Snake-case enum value -> display text, matching Rails' String#humanize
  // closely enough for format/format_detail ("mass_market" -> "Mass market").
  const humanize = (s) => {
    const t = String(s == null ? "" : s).replace(/_/g, " ").trim();
    return t ? t[0].toUpperCase() + t.slice(1) : t;
  };

  // A raw string -> ISBN-13, or null. Accepts an ISBN-13 as-is and converts a
  // 10-digit ISBN (matches lib/isbn.rb's to_13: 978 prefix, recomputed check).
  const toIsbn13 = (raw) => {
    const s = (raw || "").replace(/[^\dXx]/g, "").toUpperCase();
    if (/^\d{13}$/.test(s)) return s;
    if (!/^\d{9}[\dX]$/.test(s)) return null;
    const core = "978" + s.slice(0, 9);
    let sum = 0;
    for (let i = 0; i < 12; i++) sum += +core[i] * (i % 2 ? 3 : 1);
    return core + ((10 - (sum % 10)) % 10);
  };

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
    const es = db.prepare("SELECT id, format, format_detail, publisher, year, page_count, disposition, cover_artist, reading_status, isbn10, isbn13, isfdb, goodreads, thumb FROM editions WHERE entry_id = ?");
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
      `SELECT id, kind, title, subtitle, authors, series, series_position, year, owned, wishlisted, isbn10, isbn13, goodreads, thumb
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
              e.owned, e.wishlisted, e.isbn10, e.isbn13, e.goodreads, e.thumb, i.edition_id AS matched
       FROM isbn_index i JOIN entries e ON e.id = i.entry_id WHERE i.isbn13 = ?
       ORDER BY (i.edition_id IS NULL), (e.owned = 0) LIMIT 1`
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

  // The one linkable-id map, mirroring EditionIdentifier::EXTERNAL_URL_BY_TYPE.
  // ISBNs deliberately don't link (no single right destination).
  const ID_URL = {
    isfdb: (v) => `https://www.isfdb.org/cgi-bin/pl.cgi?${encodeURIComponent(v)}`,
    goodreads: (v) => `https://www.goodreads.com/book/show/${encodeURIComponent(v)}`,
  };

  const idSpan = ([label, v, url]) =>
    `<span><b>${label}</b> ${url ? `<a href="${esc(url)}" target="_blank" rel="noopener">${esc(v)}</a>` : esc(v)}</span>`;

  // The mono identifier footer — same shape as Ui::EditionCardComponent on
  // the web (docs/DESIGN_SYSTEM.md "Edition card"): ISBNs on one line, the
  // linkable ids on the next.
  function idFooter(e) {
    const isbns = [["ISBN-13", e.isbn13], ["ISBN-10", e.isbn10]].filter(([, v]) => v);
    const links = [
      ["ISFDB", e.isfdb, e.isfdb && ID_URL.isfdb(e.isfdb)],
      ["Goodreads", e.goodreads, e.goodreads && ID_URL.goodreads(e.goodreads)],
    ].filter(([, v]) => v);
    if (!isbns.length && !links.length) return "";
    return (
      (isbns.length ? `<div class="ids">${isbns.map(idSpan).join("")}</div>` : "") +
      (links.length ? `<div class="ids">${links.map(idSpan).join("")}</div>` : "")
    );
  }

  // Copy disposition -> lozenge. Mirrors Copy::DISPOSITION_LABELS.
  const DISPOSITION = {
    owned: ["owned", "OWNED"], replaced: ["other", "REPLACED"], sold: ["other", "SOLD"],
    given_away: ["other", "GIVEN AWAY"], lost: ["other", "LOST"],
  };

  // Reading.status -> lozenge, mirrors Ui::EditionCardComponent#reading_badge
  // on the web (docs/DESIGN_SYSTEM.md, "Edition card") — "info"/"accent"
  // are the exact same variant names Ui::BadgeComponent uses, added
  // 2026-09-04 so Read/Reading stop colliding with Owned's green
  // (.pill.info blue, .pill.accent purple — pocket.css) and DNF/TBR's
  // neutral gray respectively.
  const READING = {
    reading: ["accent", "READING"], read: ["info", "READ"],
    dnf: ["default", "DNF"], tbr: ["default", "TBR"],
  };

  // 2026-09-04: same reorg as the web edition card — headline (bold, top)
  // promoted to publisher · year · pages, falling back to format when
  // that's all there is; a lozenge row (ownership, then reading status);
  // format + cover artist demoted to a muted detail line underneath.
  function editionCardHtml(e, matched) {
    const thumb = blobUrl(e.thumb);
    const publisherLine = [e.publisher, e.year, e.page_count ? e.page_count + " pages" : null].filter(Boolean).join(" · ");
    const formatText = humanize(e.format_detail || e.format) || "Edition";
    const headline = publisherLine || formatText;
    const detail = [formatText, e.cover_artist].filter(Boolean).join(" · ");
    const ownedPill = DISPOSITION[e.disposition];
    const readPill = READING[e.reading_status];
    return `<div class="edition${matched ? " matched" : ""}">
      ${thumb ? `<img src="${thumb}" alt="">` : `<div class="noimg">?</div>`}
      <div class="body">
        <div class="headline">${esc(headline)}${matched ? ` <span class="meta">· matched</span>` : ""}</div>
        ${ownedPill || readPill ? `<div class="pills">
          ${ownedPill ? `<span class="pill ${ownedPill[0]}">${ownedPill[1]}</span>` : ""}
          ${readPill ? `<span class="pill ${readPill[0]}">${readPill[1]}</span>` : ""}
        </div>` : ""}
        <div class="meta">${esc(detail)}</div>
        ${idFooter(e)}
      </div>
    </div>`;
  }

  // A pure wishlist entry (no editions at all — see docs, "is a wishlist
  // item connected to an edition?": no) gets the same card shape as an
  // edition — same size/left-aligned image — but there's no
  // publisher/year/pages to headline with, so the WISHLIST lozenge just
  // takes that line's place, same pills-row styling an edition card's own
  // ownership/reading lozenges use (flush top-left — a first cut had this
  // right-justified, which read fine in isolation but on a real device
  // left it stranded at the far right of the screen since .body stretches
  // to the row's full width; fixed 2026-09-04). `idFooter` reuses the
  // exact same footer an edition card uses; a wishlist item never has an
  // isfdb id (nothing's been matched yet), but does carry isbn10/isbn13
  // and a goodreads id, which idFooter already renders fine given only
  // some of the fields it knows.
  function wishlistCardHtml(row) {
    const thumb = blobUrl(row.thumb);
    return `<div class="edition wishlist-card">
      ${thumb ? `<img src="${thumb}" alt="">` : `<div class="noimg">?</div>`}
      <div class="body">
        <div class="pills"><span class="pill wish">WISHLIST</span></div>
        ${idFooter(row)}
      </div>
    </div>`;
  }

  // A result: a plain-text head (title/series/author — no image; a work
  // and a wishlist item are laid out identically here), then one full
  // card per printing a copy has passed through (docs/MOBILE.md), or —
  // for a pure wishlist entry with no editions — one wishlistCardHtml
  // instead. A work that's *also* wishlisted (you own one printing but
  // still want another) keeps the compact inline WISHLIST lozenge here in
  // the head, since it already gets real edition cards below.
  function entryHtml(row, note) {
    const eds = row.editions || [];
    const wishlistOnly = row.wishlisted && eds.length === 0;

    return `
      ${note ? `<div class="meta alt">${esc(note)}</div>` : ""}
      <div class="title">${esc(row.title)}${row.series ? ` <span class="meta">— ${esc(row.series)}${row.series_position ? " #" + esc(row.series_position) : ""}</span>` : ""}</div>
      <div class="meta">${esc(row.authors || "")}${row.year ? " · " + row.year : ""}</div>
      ${row.wishlisted && !wishlistOnly ? `<span class="pill wish">WISHLIST</span>` : ""}
      ${wishlistOnly ? wishlistCardHtml(row) : ""}
      ${eds.map((e) => editionCardHtml(e, row.matched && e.id === row.matched)).join("")}`;
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
    for (const row of rows) els.results.appendChild(el("entry", entryHtml(row)));
  }

  // A single-ISBN result (from a scan or a typed ISBN): one entry, or NEITHER.
  function renderLookup(code, row) {
    clearResults();
    els.empty.hidden = true;
    if (row) {
      // A work-level hit with no matched edition = you own a *different*
      // printing than the one just scanned.
      const note = row.kind === "work" && !row.matched ? "you own a different edition:" : null;
      els.results.appendChild(el("entry", entryHtml(row, note)));
    } else {
      els.results.appendChild(el("entry neither", `
        <div class="head">
          <div class="noimg">✕</div>
          <div class="body">
            <div class="title">Not in your collection</div>
            <div class="meta">${esc(code)} — not owned, not on your wishlist</div>
            <span class="pill neither">NEITHER</span>
          </div>
        </div>`));
    }
  }

  let searchTimer = null;
  function runSearch() {
    clearTimeout(searchTimer);
    searchTimer = setTimeout(() => {
      const raw = els.q.value.trim();
      // Only treat the query as an ISBN when it's nothing but ISBN characters —
      // a title with a number in it still goes to text search.
      if (/^[\dXx\s-]+$/.test(raw)) {
        const isbn13 = toIsbn13(raw);
        if (isbn13) return renderLookup(isbn13, byIsbn(isbn13));
      }
      render(search(els.q.value));
    }, 120);
  }

  // --- barcode scanner --------------------------------------------
  let detector = null;
  let stream = null;
  let scanPoll = null;
  let scanBusy = false;

  async function openScanner() {
    if (!db) return setStatus("no snapshot yet — connect once first", "error");
    try {
      detector = detector || new window.BarcodeDetector({ formats: ["ean_13", "upc_a"] });
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
      const values = (await detector.detect(els.cam)).map((c) => c.rawValue);
      const ean = values.find((v) => /^\d{13}$/.test(v));
      const upc = values.find((v) => /^\d{12}$/.test(v));
      if (ean) {
        closeScanner();
        els.q.value = "";
        renderLookup(ean, byIsbn(ean));
      } else if (upc) {
        // A US mass market carrying a publisher retail UPC instead of a
        // Bookland EAN — the UPC doesn't map to an ISBN, so send them to
        // the search box.
        closeScanner();
        setStatus("that's a UPC, not an ISBN — type the ISBN from the cover", "error");
        els.q.focus();
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
      // If a controller is already in place, a later controllerchange means a
      // new version has taken over — reload once so the page runs fresh code.
      // (Skipped on the very first visit, where no-controller -> controller
      // fires the same event without an update having happened.)
      if (navigator.serviceWorker.controller) {
        let reloading = false;
        navigator.serviceWorker.addEventListener("controllerchange", () => {
          if (reloading) return;
          reloading = true;
          window.location.reload();
        });
      }
      navigator.serviceWorker.register(cfg.serviceWorkerUrl, { scope: cfg.scope }).catch(console.error);
    }
    // Ask the browser to keep our storage (the snapshot + token) off the
    // eviction list. Installed PWAs usually get this for free; asking is
    // harmless and covers the in-browser case too.
    navigator.storage?.persist?.().catch(() => {});
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
