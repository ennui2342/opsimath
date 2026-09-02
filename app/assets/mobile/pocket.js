// opsimath pocket — offline shop-lookup PWA client (docs/MOBILE.md).
// Downloads the snapshot.sqlite3, keeps it in IndexedDB, queries it with
// sql.js. No framework.
(() => {
  "use strict";
  const cfg = window.__pocket || {};
  const els = {
    status: document.getElementById("status"),
    q: document.getElementById("q"),
    results: document.getElementById("results"),
    empty: document.getElementById("empty"),
    form: document.getElementById("search"),
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

  // --- search ----------------------------------------------------------
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

    for (const row of rows) {
      if (row.kind === "work") {
        const es = db.prepare("SELECT format, format_detail, publisher, year, thumb FROM editions WHERE entry_id = ?");
        es.bind([row.id]);
        row.editions = [];
        while (es.step()) row.editions.push(es.getAsObject());
        es.free();
      }
    }
    return rows;
  }

  const blobUrl = (bytes) =>
    bytes && bytes.length ? URL.createObjectURL(new Blob([bytes], { type: "image/webp" })) : null;

  function render(rows) {
    els.results.querySelectorAll("img[src^=blob]").forEach((i) => URL.revokeObjectURL(i.src));
    els.results.innerHTML = "";
    els.empty.hidden = rows.length > 0 || norm(els.q.value) === "";

    for (const row of rows) {
      const card = document.createElement("div");
      card.className = "card";

      const thumb = blobUrl((row.editions && row.editions.find((e) => e.thumb) || {}).thumb || row.thumb);
      const fmt = (e) => [e.format_detail || e.format, e.publisher, e.year].filter(Boolean).join(" · ");

      card.innerHTML = `
        ${thumb ? `<img src="${thumb}" alt="">` : `<div class="noimg">?</div>`}
        <div class="body">
          <div class="title">${esc(row.title)}${row.series ? ` <span class="meta">— ${esc(row.series)}${row.series_position ? " #" + esc(row.series_position) : ""}</span>` : ""}</div>
          <div class="meta">${esc(row.authors || "")}${row.year ? " · " + row.year : ""}</div>
          <span class="pill ${row.owned ? "owned" : "wish"}">${row.owned ? "OWNED" : "WISHLIST"}</span>
          ${row.editions && row.editions.length ? `<div class="editions">${row.editions.map((e) => `<div>${esc(fmt(e))}</div>`).join("")}</div>` : ""}
        </div>`;
      els.results.appendChild(card);
    }
  }

  let searchTimer = null;
  function runSearch() {
    clearTimeout(searchTimer);
    searchTimer = setTimeout(() => render(search(els.q.value)), 120);
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

    await sync();
  }

  boot().catch((e) => { console.error(e); setStatus("failed to start", "error"); });
})();
