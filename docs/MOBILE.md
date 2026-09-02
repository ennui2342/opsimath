# Mobile: the offline shop-lookup PWA

Status: **spec, not built.** Written early — before the client exists —
because the offline requirement constrains the *server* data model, and
those constraints are cheapest to honour while the model is still being
built (`PHILOSOPHY.md` principle 15's "deferred, not foreclosed" applied
concretely).

## The one use case

Standing in a bookshop, holding a book:

- **Do I already own an edition of this?** (yes / no)
- If not, **is it on my wishlist?** (yes / no)
- Show enough to disambiguate an edition: title, author(s), series, and
  for each edition I own — format, publisher, year — plus a small cover
  thumbnail.

That's the whole v1. No adding, no editing, no reading log, no storage
location ("Office shelf 3" is explicitly out of scope), no notes, no
reviews. **Read-only.**

It has to work with no signal — bookshop basements, rural high streets —
so every answer comes from data already on the phone.

## Where this sits relative to Turbo Native

`PHILOSOPHY.md` principles 17/18 line up **Turbo Native** for an eventual
mobile client, and that still holds — but for a *different* client. Turbo
Native wraps the live Hotwire app in a native shell; every screen needs
connectivity. It was chosen over a PWA for *navigation feel* (the earlier
HTMX-in-a-PWA pain), never as an offline story — principle 15 says
outright "opsimath has no offline-capable client today."

This PWA is not a reversal of that. It's the right tool for a job Turbo
Native cannot do: **offline, read-only lookup**. If a rich *interactive*
mobile client is ever wanted (add a book from your phone, log a read),
Turbo Native is still the answer for that, and the two can coexist — this
PWA stays a focused single-purpose tool.

And because it's read-only, principle 15's multi-device offline-sync
machinery (librarium's `000018`–`000021`: last-write-wins timestamps,
tombstones, per-device cursors) stays deferred. There is no write path,
so there is nothing to reconcile. One-way snapshot, full stop.

## Architecture: a one-way snapshot

The data is tiny and changes slowly (~2,000 works / ~2,000 editions /
~300 wishlist items; the read-model subset is a few MB). So: the server
builds a **snapshot artifact**, the phone downloads it when it has wifi,
and all lookups run against the local copy. Not a live API per request,
not incremental sync — just "here is snapshot version N."

### The snapshot artifact

**Contents** — one flat list of *entries*, each a book you own or have
wishlisted, so the client runs **one** search / one barcode lookup, not
one per collection. A catalogued work and an unmatched wishlist item are
both an entry; a work's one-to-many editions hang off it and are joined
only after a hit, never searched. Built by `Mobile::ShopView`.

```
entries      id ("work:<id>" | "wishlist:<id>"), kind, title, subtitle,
             authors, series, series_position, year,
             owned, wishlisted, thumb,
             search_title, search_author, search_series,
             isbn10, isbn13          -- entry-level: kind='wishlist' only
editions     entry_id, format, publisher, year, isbn10, isbn13, thumb
                                     -- kind='work' only; the editions you own a copy of; 1..n
isbn_index   isbn13, entry_id, edition_id   -- every ISBN form folded to 13; edition_id null for wishlist
meta         version, generated_at
```

- `owned` = any `Copy` with `disposition: "owned"` for an edition of the
  work. `wishlisted` = a `WishlistItem` (matched to the work, or its own
  `kind='wishlist'` entry when unmatched — the only case today, see below).
- `search_*` are normalised (lowercased) for the client's fuzzy match.
- barcode: `isbn_index` → `entries` row (+ the matched `editions` row);
  text: fuzzy over `entries.search_*` → then load `editions` on a hit.

**Format** — SQLite file (`snapshot.sqlite3`), thumbnails stored as
`BLOB` columns. One file, real indexed queries, thumbnails travel with
it. Read on the client via `wa-sqlite` over OPFS. (A one-hour spike on
`wa-sqlite` on a real Android phone comes first — if it's genuinely
unworkable the fallback is a gzipped-JSON payload held in memory, so the
generator keeps its serialisation behind one seam — but SQLite is the
decision, not a maybe.)

Note: nothing sets `WishlistItem#work_id` today — the Goodreads flow
deletes a wishlist item on acquisition rather than linking it — so in
practice every wishlist entry is `kind='wishlist'` and no work entry
comes back `wishlisted`. `ShopView` handles the matched case anyway
(costs nothing) in case that flow ever changes.

**Thumbnails** — a single declared Active Storage variant, ~120×180,
WebP, pre-generated (eager `process`, plus a one-off backfill) so
building the snapshot is a copy, never on-demand image processing:

- Owned editions: `Edition.cover_image.variant(:thumb)`.
- Wishlist entries: these carry only a bare `cover_url` string today, not
  an attachment. They get a thumbnail too — so `WishlistItem` needs a
  real `cover_image` attachment: download `cover_url` into Active Storage
  when the entry is created (or a backfill job over existing ones), then
  the same `:thumb` variant applies. See constraint 6.

**Size budget: < 25 MB.** Current scale lands around 15 MB. Revisit the
format if the collection multiplies.

**Versioning + endpoint** — served from a stable path behind an
`ApiToken` (the existing single-user token mechanism, `PHILOSOPHY.md`
principle 19), with a version/ETag so the client only re-downloads when
it actually changed:

- `GET /mobile/snapshot/version` → `{ version, generated_at, bytes }`
- `GET /mobile/snapshot` → the file (supports conditional GET)

**Generation** — a background job produces the artifact and bumps the
version. Cadence: on every deploy, plus a nightly rebuild (the data
changes via the hourly Goodreads sync). Cheap — it's a single query and a
few MB.

## Refresh behaviour

**Automatic, on wifi.** When the PWA is open (or via a Background Sync /
Periodic Background Sync registration where supported) and the device is
on an unmetered connection, it polls `/mobile/snapshot/version`; if the
server version is newer, it downloads the new snapshot in the background
and swaps it in atomically.

**Plus a manual check.** v1 also shows a "last updated 3 days ago" line
with a "check now" button — for the case where you know you added
something at the desk this morning and want it before walking into the
shop. Same download path; ignores the metered-connection gate since the
user asked for it explicitly.

Metered-connection downloads are skipped (a 15 MB pull shouldn't land on
mobile data unprompted). `navigator.connection` gates this where
available; where it isn't, default to "only when the SW says we're
online and the user opened the app," and lean on the fact that a stale
snapshot is still fully functional.

## The client (PWA)

- **Install**: standard web app manifest + `beforeinstallprompt`, "add to
  home screen". Served by the Rails app (the `app/views/pwa/` scaffold is
  already there, currently unwired — routes commented in `config/routes.rb`).
- **Local store**: the snapshot SQLite in OPFS via `wa-sqlite`; a small
  bit of app state (current snapshot version, last-checked time) in
  `localStorage`.
- **Offline shell**: a Service Worker precaches the app shell (HTML/CSS/JS
  for the lookup screen) so the PWA opens with no network. This is *only*
  the lookup UI — not the full opsimath web app.
- **Lookup flow**:
  1. **Barcode** — `BarcodeDetector` (native in Android Chrome) over a
     `getUserMedia` camera stream; the EAN-13 is an ISBN-13, matched
     exactly against the indexed identifiers. Fallback to a WASM decoder
     (`zxing-wasm`) if `BarcodeDetector` is unavailable.
  2. **Text** — type title / author; fuzzy match against the normalised
     search keys.
- **Result**: one of three states, unambiguous and glanceable —
  - **Owned** — green; list the owned editions (format · publisher ·
    year) with thumbnails.
  - **On wishlist** — amber; show the wishlist entry.
  - **Neither** — grey; "not in the collection or wishlist".

The scan UX is the make-or-break — see "To validate" below.

## Constraints on ongoing server development

These are the reason this doc exists now. Honour them as the data model
and features are built:

1. **Identifier completeness.** Every edition that *could* have an ISBN
   ends up with both `isbn10` and `isbn13` in `EditionIdentifier`,
   normalised and check-digit valid. Barcode scans give EAN-13 — don't
   make the client derive it. Pre-ISBN books stay title/author-only, and
   that's fine; the rule is that the enrichment pipeline must never drop
   an ISBN it had access to.
2. **A declared `:thumb` variant** (~120×180 WebP), generated eagerly for
   every edition *and every wishlist entry* with a cover, so the snapshot
   export never does image work.
3. **One "shop view" read model.** "Do I own an edition of this work" and
   "is this work wishlisted" must each be answerable in a single query,
   and serialisable. Resist spreading that logic across
   controllers/helpers in ways a batch export can't reproduce (same
   spirit as `Reading` count being a derived query, not a stored field).
   This read model doubles as the shape of any future public API.
4. **The snapshot generator is first-class**, tested, and rebuilt on
   deploy. If a schema change breaks it, that's a failing build, not a
   surprise.
5. **Zero server round-trips in the lookup path.** The app may grow
   online features later, but the shop use case must be answerable purely
   from the local snapshot. Anything it needs must be a plain,
   denormalisable column/association — never a runtime computation that
   needs the app running.
6. **Wishlist parity with editions for lookup.** Capture a
   `WishlistItem`'s ISBN when it's known (so a scan matches a not-yet-owned
   book), and give `WishlistItem` a real `cover_image` Active Storage
   attachment — download `cover_url` into it on create, backfill the
   existing ~300 — so wishlist entries carry a `:thumb` the same way
   editions do. This means `DATA_MODEL.md`'s deferred "downloading/storing
   an image is deferred until the book is actually acquired" note gets
   revised: the wishlist thumbnail is now in scope.

## Non-goals (v1) / deferred

- Any write path (adding, editing, logging a read). If it ever happens,
  `PHILOSOPHY.md` principle 15 + librarium's sync migrations are the
  reference — not before.
- iOS. The target is Android; iOS PWA support is weaker and not a
  priority.
- Storage location, condition, acquisition data, notes, reviews, reading
  history.
- Full-size covers — thumbnails only.
- App-store distribution — it's an installed PWA.

## Settled

- Client: PWA first; Turbo Native still lined up for a later interactive
  client.
- Snapshot: SQLite, one file, thumbnails as BLOBs.
- Refresh: automatic on wifi **and** a manual "check now" button.
- Scope: owned / wishlist / neither. No location, condition, notes, etc.
- Wishlist entries get a real `cover_image` attachment and a `:thumb`.

## To validate before building further

- **`wa-sqlite` + OPFS on a real Android phone** — reading the snapshot,
  running the ISBN + fuzzy-text queries. If unworkable, fall back to a
  gzipped-JSON payload (the generator keeps serialisation behind one
  seam).
- **`BarcodeDetector` on the same phone** — the scan-in-a-shop UX is the
  make-or-break; confirm it before committing to the PWA over native.
