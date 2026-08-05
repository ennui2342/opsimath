# Goodreads integration

This is the first real feature built, ahead of any UI — see `PHILOSOPHY.md`
principle 20 for why. Scope for this phase, deliberately bounded: bulk
import, ongoing sync, and the enrichment hooks around both. No UI (Rails
console / a minimal read-only view is enough to verify results); no
reverse sync (opsimath → Goodreads) — that's an explicit "down the line"
per the discussion that produced this doc, not forgotten.

Grounded directly in two things checked before writing a line of this:
the real `import/goodreads_library_export*.csv` (2,306 books, read
directly — see column notes below) and the three existing, working
`aswarm` pipelines (`goodreads-librarium-sync`, `-reading-sync`,
`-read-sync`) that already do most of this for librarium. Where those
pipelines settled something through hard-won experience, it's ported, not
rediscovered.

## Phase 1: bulk CSV import

One-time (or re-runnable) import of the full export — the only way to get
complete history, since the RSS feeds used in phase 2 cap at 100 items
per shelf with no pagination (a real Goodreads limitation, not a design
choice — confirmed in `goodreads-librarium-sync.yaml`'s known-limitations
section).

### Column mapping

| CSV column | Maps to | Notes |
|---|---|---|
| `Book Id` | `EditionIdentifier` (`id_type: goodreads`) | Goodreads' own id is edition-level (confirmed live: each printing/ISBN has its own), not work-level — the export has no separate work id. Relevant to dedup: two rows with different `Book Id` can legitimately be the same `Work`, different editions. |
| `Title` | `Work.title`, after series-suffix parsing (below) | |
| `Author`, `Author l-f`, `Additional Authors` | `WorkContributor` (role `author`) | |
| `ISBN`, `ISBN13` | `EditionIdentifier` (`isbn10`/`isbn13`) | |
| `My Rating` | `Reading.rating` | Goodreads is 0–5 whole stars; opsimath's scale is already 0–5 half-star (chosen against the scifipraxis pipeline, not for this) — maps on directly, no conversion needed, unlike librarium's 1–10 scale which needed doubling. `0` means unrated, not zero-star — leave `Reading.rating` blank, don't store `0`. |
| `Publisher`, `Binding`, `Year Published` | `Edition` fields (`publisher`, `format`/`format_detail` from `Binding` text, `publish_date`) | |
| `Number of Pages` | **Not mapped** — deliberately not imported at all | Confirmed against real conflict data that it disagrees with ISFDB often enough (558 real `PendingDecision`s), and carries little enough collector value, that it's not worth treating as a trusted baseline — same shape of call as `Read Count`, just for a field low-stakes enough that the resolution is "don't import it," not "reconcile it." Left entirely to isfdb enrichment to fill in; see the enrichment addendum below. |
| `Original Publication Year` | `Work.original_publication_year` | |
| `Date Read` | `Reading.date_finished`, when `read_dates` (below) doesn't already cover it | Format `YYYY/MM/DD` — different from `read_dates`' `YYYY-MM-DD`, confirmed by direct inspection. Parse both, don't assume one format everywhere in this file. |
| `Date Added` | *Not* `Copy.acquired_date` | This is when the row was added to Goodreads, not when the book was acquired — often logged well after actual purchase. Left unmapped; `Copy.acquired_date` stays blank on import, filled in by hand later if known. |
| `Bookshelves` (plural) | `Tag` / `Genre` | Free-form shelf labels a user assigned — confirmed via direct inspection to include genuine genre-ish tags (`sci-fi`, `fantasy`, `philosophy`, `essays`, `ai`, `business`, `games`) alongside the status shelves. Match against Thema-seeded `Genre` names where they align; everything else becomes a `Tag`. |
| `Exclusive Shelf` | Drives the shelf → entity mapping below | The authoritative single status shelf, distinct from `Bookshelves` — confirmed real values in this export: `wishlist`, `to-read`, `currently-reading`, `read`, `did-not-finish` (not `dnf` — exact string matters for the ongoing-sync matching too). |
| `My Review` | `Review` (`channel: goodreads`) | A published Goodreads review is a real published review, not a private note — see `Review.channels`' note below. |
| `Private Notes` | `Reading.private_notes` | |
| `Spoiler` | Not mapped for now | Low-value; revisit only if it turns out to matter. |
| `Read Count` | **Not mapped — ignored entirely** | Confirmed spurious: an artifact of Goodreads marking every book "read" at the date of entry when the library was first bulk-added, without real per-instance dates. See below — `read_dates` is the only trusted signal for reread count. |
| `read_dates` | `Reading` rows (one per actual read) | See below. |
| `Owned Copies` | `Copy` rows | One minimal `Copy` per count (`disposition: owned`, everything else blank) — captures "you own N copies of this" without pretending to know condition/acquisition detail that Goodreads never had. Real cataloging detail (condition, storage, inscriptions) gets filled in by hand later, per `PHILOSOPHY.md` principle 6 — this import doesn't try to fake it. |

### Series-in-title parsing

Goodreads' `Title` embeds series info (`"Neuromancer (Sprawl #1)"`).
Reuse the exact heuristic already proven in `goodreads-librarium-read-sync.yaml`'s `prep` step rather than re-deriving one: find `" ("`, treat it as a series suffix only if the text from there contains `#` (a genuinely parenthetical title — a date, a publisher name — doesn't). The stripped title becomes `Work.title`; the parsed series name/position feeds `WorkSeries` (matched against an existing `Series` by name, created if new). The raw Goodreads title isn't kept as a `WorkAlternateTitle` — it's a display convention of Goodreads' own UI, not a real alternate title a publisher used.

### `read_dates` is definitive; `Read Count` is not trusted at all

Checked directly: of the 6 books in this export with `Read Count > 1`,
only 2 have populated `read_dates` (semicolon-separated `start,end` pairs
— e.g. `2016-01-30,2016-03-27;2024-10-05,2024-10-15` for a book read
twice). Confirmed with Mark: this isn't a data-recovery gap to work
around — `Read Count` itself is spurious for this library, an artifact of
how it was first bulk-added to Goodreads (marked "read" at date of entry,
without real per-instance dates). `read_dates` is the sole source of
truth for reread history; `Read Count` isn't imported or reconciled
against at all.

Policy, simplified accordingly: where `read_dates` has N pairs, create N
`Reading` rows with real `date_started`/`date_finished` — this is the
genuine multi-read case. Where `read_dates` is blank, create exactly
**one** `Reading` using `Date Read` as `date_finished` (blank if that's
missing too) — no annotation, no flagged gap, because this is the
ordinary single-read case, not data loss. "How many times has this been
read" stays a derived query over real `Reading` rows either way, per
principle 4 — never a count copied in from an untrusted source field.

### Enrichment at import time

A single batch job (Solid Queue, per `PHILOSOPHY.md` principle 13) over
imported `Edition`s against `isfdb-adapter` — same `EnrichmentRecord`/
`field_sources`/`PendingDecision` machinery already designed, not new
mechanism. `isfdb-adapter`'s current API is used as-is; revisit its shape
only if real friction shows up using it here, not speculatively.

**Built as `IsfdbEnrichmentJob`** (`Isfdb::Client`,
`Enrichment::FieldApplier`, `Enrichment::IsfdbEditionEnricher`; triggered
via `bin/rails isfdb:enrich_editions`). A few things only became clear by
actually building this and checking the live mirror directly (read-only
queries through the running adapter pod, not guessed):

- **`isfdb-adapter` had no external route at all before this** — ClusterIP
  only, no `Ingress`, despite `isfdb-adapter.k8s.ecafe.org` already
  resolving via DNS (to Traefik's IP, matching every other `*.k8s.ecafe.org`
  service — just with no matching `Ingress` rule, so nothing was actually
  listening on that hostname). Added `k8s` repo's `isfdb/ingress.yaml`
  (Traefik only, matching `home-assistant`/`grafana`'s pattern — an
  internal API other services consume, not something browsed directly,
  so no Tailscale funnel the way `librarium`/`wallabag` have). `ISFDB_
  ADAPTER_URL` is plain port 80 (Traefik), not `:8080` (the cluster-
  internal service port) — a real bug in the first version of that line,
  caught by testing connectivity rather than assuming the URL was right.
  DNS for `k8s.ecafe.org` names resolves to a cluster-internal-only IP
  through this session's own Tailscale-routed DNS, but the real LAN IP
  (`192.168.0.8`) answers correctly with the right `Host` header —
  worth checking whether Tailscale's DNS config misdirects other
  tailnet-connected devices the same way, independent of opsimath.
- **Edition-scoped, not Work-scoped, and ISBN-only for v1** — `/isbn/{isbn}`
  returns edition-shaped data (publisher, publish date, page count,
  cover), so `EnrichmentRecord`s here are `entity_type: "Edition"`, not
  `"Work"`. `/search`'s fuzzy title/author matching is deliberately out
  of scope for v1 — a real, harder false-positive-match problem, not
  rushed in alongside this.
- **`description`/`categories` are hardcoded empty in the adapter's actual
  code**, not just in its README's example — confirmed by reading
  `adapter.py` directly. `titles.title_synopsis` in the live mirror turned
  out to be an `int(11)` — a dangling reference to ISFDB's real synopsis
  table, which `refresh.py`'s import filtering doesn't currently pull in
  at all. Getting real descriptions would mean changing `isfdb-adapter`
  itself (a separate project) to import that table too; out of scope
  here. `notes` (1.2M rows, real bibliographic/editorial trivia — printing
  history, series cross-references — not plot synopses) exists in the
  mirror and could enrich `Work.notes` someday, but isn't wired in now.
- **Cover coverage is good**: 861k/957k `pubs` (~90%) have a
  `pub_frontimage` in the live mirror, so `Edition.cover_image` (Active
  Storage, downloaded and kept — never hotlinked) should fill for most
  editions matched. A cover-download failure is logged and skipped, never
  raised — it shouldn't block the other fields from applying.
- **A real, verified `pub_ptype` -> `format`/`format_detail` mapping**,
  not a guess: queried the live distribution directly (`tp` 264k, `ebook`
  214k, `hc` 159k, `pb` 152k, plus `digital audio download`, `digest`,
  `audio CD`, `pulp`, and print-size terms — `quarto`, `octavo`, `A4` —
  that don't map onto either our `format` enum or ONIX `format_detail` at
  all). Only the confident cases are mapped
  (`Enrichment::IsfdbEditionEnricher::FORMAT_BY_PTYPE`); the long tail is
  left untouched rather than forced into a guessed bucket.
- **The empty-fills-automatically / non-empty-creates-a-`PendingDecision`
  policy** (`Enrichment::FieldApplier`) is a real, generic, reusable gate,
  not bespoke per-field logic — and re-flagging the same already-pending
  conflict on a second run reuses the existing `PendingDecision` rather
  than creating a duplicate, checked via `payload @>` containment.
- **`Editions` are skipped, not retried, once already attempted** — the
  job's scope is "has an ISBN identifier and no prior `isfdb`
  `EnrichmentRecord` yet," so a clean re-run only picks up new editions,
  same idempotency shape as `Goodreads::Importer`.

Verified with WebMock against real response shapes (curled live from the
adapter after the Ingress fix, not fabricated) — 72/72 tests pass,
RuboCop/Brakeman clean. **Also run for real against the full 2,306-book
library** (2026-08-05): of 1,811 `Edition`s with a real ISBN, 1,431
matched in the ISFDB mirror (380 didn't — real, expected coverage gaps,
not an error) — 1,367 editions got a real downloaded cover image, 1,306
got a `language` value (never populated by the Goodreads import at all),
1,343 editions now carry real `field_sources` provenance. 2,705
`PendingDecision`s were raised for genuine field conflicts.

**That real conflict data led to a real schema fix, not just a bigger
review queue.** Breaking the 2,705 down by field (`publish_date` 1,291,
`publisher` 846, `page_count` 558, `format` 10) and actually looking at
the `publish_date` ones surfaced that 986 of 1,291 (76%) weren't real
disagreements at all — they were `Edition.publish_date_precision ==
"year"` (our own Jan-1-fabricated placeholder, from Goodreads only ever
giving a bare year) being "contradicted" by a genuinely more precise
ISFDB value in the *same* year. That's a refinement, not a conflict —
and it only looked like one because `publish_date`/`publish_date_precision`
(a `date` column + a companion enum) couldn't represent "I only know the
year" without lying about the day/month in the `date` column itself.

**Fixed at the representation, not just the comparison**: replaced
`publish_date`/`publish_date_precision` with a single EDTF-formatted
string column (`"1978"`, `"1978-06"`, `"1978-06-15"` — see
`DATA_MODEL.md`'s `Edition.publish_date` entry for the full reasoning).
`Enrichment::IsfdbEditionEnricher#apply_publish_date` now compares by
string-prefix: if the proposed value extends what we already know (same
year, more digits), it's applied directly; if what we already have
already extends the proposed value, nothing changes; only a genuine
disagreement (neither extends the other — different year, or same
precision but a different value) goes through `FieldApplier`'s normal
conflict gate. Added `IsfdbEditionEnricher.reprocess(edition, payload)` —
re-applies an already-fetched `raw_payload` without a new fetch, the
concrete use `EnrichmentRecord`'s "keep the full payload" design was
built for — and used it to retroactively re-resolve the existing backlog
against the fixed logic, without hitting isfdb-adapter again. Confirmed
against the real data: `publish_date` `PendingDecision`s dropped from
1,291 to 305 (all genuine year-level disagreements), 1,033 editions
gained real month/day precision (up from 2), total pending conflicts
1,291+1,414 -> 305+1,414 (2,705 -> 1,719).

**Two more fixes followed from actually analyzing the field breakdown**,
not just accepting the count:

- **`publisher` (846) — split by substring-containment, then by whether
  the extra text carries real information.** 31 were pure formatting
  noise (`"Newcon Press"` vs `"NewCon Press"`, `"Pan/Ballantine"` vs
  `"Pan / Ballantine"`) — a real `FieldApplier` comparison gap, fixed by
  normalizing (case/whitespace/punctuation-insensitive) before deciding
  something changed. Of the remaining 521 substring-containing pairs,
  splitting by whether either side carries a territory qualifier
  (`UK`/`US`/`USA`/`(UK)`/`(US)`) found 442 (85%) were plain generic-
  suffix variants (`"Tor Books"` vs `"Tor"`, `"DAW"` vs `"DAW Books"`) —
  genuinely the same publisher, safe to merge toward whichever form is
  more complete — but 79 (15%) were real regional distinctions
  (`"Orbit"` vs `"Orbit (US)"`, `"Roc"` vs `"Roc UK"`) that `PHILOSOPHY.md`
  principle 11 says matter for vintage SF collecting. `"prefer the
  longer string"` is *not* a safe blanket rule here the way it was for
  dates — length alone doesn't reliably mean "more correct," only "more
  complete when it's genuinely the same fact." `Enrichment::
  IsfdbEditionEnricher#apply_publisher` merges the generic-suffix case
  toward the more complete form directly; a region-flavored pair (or a
  genuinely unrelated one) still goes through `FieldApplier`'s normal
  conflict gate. Confirmed against the real backlog: `publisher`
  `PendingDecision`s dropped from 846 to 373 (exactly 31 + 442 resolved),
  leaving 79 region-flavored + 294 genuinely different.
- **`page_count` (558) — dropped from the Goodreads import entirely**,
  not reconciled. Mark's call: Goodreads' `Number of Pages` disagrees
  with ISFDB often enough (558 real conflicts) and matters little enough
  to a collector that it's not worth treating as a trusted baseline at
  all — closer to `Read Count`'s situation than to `publish_date`'s.
  `Goodreads::Importer#create_edition` no longer sets `page_count`;
  `Enrichment::IsfdbEditionEnricher` still applies it normally (now
  always via the ordinary empty-fill path, never a conflict, since
  nothing else claims the field first). Retroactively cleared the 1,913
  existing non-isfdb-sourced `page_count` values on real data (an honest
  gap is better than an untrusted guess) and deleted the now-moot
  `PendingDecision`s; a plain reprocess of the existing `EnrichmentRecord`
  backlog then filled `page_count` cleanly for 1,420 editions with zero
  new conflicts.

**Final real numbers** after both fixes + the retroactive reprocess:
total pending conflicts 2,705 -> 688 (`publish_date` 305, `publisher`
373, `page_count` 0, `format` 10). The remaining 688 were also analyzed,
not just left alone:
- `publish_date` (305) — genuine year-level disagreements; worth a human
  look, possibly indicating ISFDB matched a different printing under a
  reused ISBN (a caveat its own README names directly).
- `publisher` (373) — 79 region-flavored + 294 genuinely different
  strings; both are real disagreements worth a human's attention, not
  noise.
- `format` (10) — all substantive (paperback vs. hardcover, ebook vs.
  hardcover), no safe auto-resolution, genuinely need a human.

Reviewing what's left is real, separate follow-up work with no UI to do
it through yet — not a defect in this job.

### Addendum: real-data findings from building and running the importer

Implemented as `Goodreads::RowParser` (pure parsing) and
`Goodreads::Importer` (`bin/rails goodreads:import[path]`), tested against
real extracted rows (`test/fixtures/files/goodreads_sample.csv`) and then
run against the actual 2,306-row export. Several things only surfaced by
doing that — recorded here because they extend or correct what's written
above, not just implementation detail:

- **`Owned Copies` doesn't reflect "to-read is where a book becomes
  owned" in practice.** Confirmed directly: `Owned Copies` is `0` for all
  1,140 `to-read` rows and all but 12 of 819 `read` rows in the real
  export — it's essentially an unused Goodreads field for this account,
  the same shape of problem as `Read Count`. Resolved the same way:
  trust the better signal instead. The importer treats any non-wishlist
  shelf as the ownership signal and creates at least one `Copy`
  (`max(Owned Copies, 1)`), using the column only as a multiplier for the
  rare case it's genuinely > 1. Confirmed against the run: 1,985 catalog
  rows → 1,985 `Copy` rows.
- **Reading-duplication risk from Goodreads catalog churn, not from this
  design.** 7 real `(title, author)` pairs have two independent
  `read`-shelf rows for what's clearly one actual read — one row carries
  real rating/date/review, the other is an empty husk (Goodreads
  re-adding/splitting an edition leaves the old shelf entry behind with
  no data). A naive row-by-row importer would double-count these as
  rereads. Worse: in 2 of the 7 cases the empty row appears *before* the
  real one in the file, and in one case (`The Medusa Chronicles`) both
  rows carry the *same* rating, so rating alone can't discriminate real
  from cruft either — only the date can. Fixed by grouping all of a
  work's `read`/`did-not-finish` rows together and deriving Reading rows
  from the *union* of dated read events across the group, not per-row —
  this resolves every real case correctly regardless of file order, and
  needed no `PendingDecision` fallback in practice (all 7 cases resolved
  cleanly). Verified against an independent recount: 815 expected
  completed+dnf `Reading` rows, 815 created.
- **`Contributor.sort_name`** ("Author l-f", e.g. "Delany, Samuel R.") is
  only available for the primary author — `Additional Authors` is a raw
  comma-separated name list with no l-f equivalent. Only the primary
  author gets `sort_name` populated on import.
- **`Work.literary_form`** (renamed from `work_type` — see
  `DATA_MODEL.md`'s note on why) **mostly has no signal in the CSV — but
  three `Bookshelves` labels are an exact, unambiguous exception.**
  `anthology`, `collection`, and `essays` map directly onto three of
  `literary_form`'s own enum values (confirmed against real rows — e.g.
  "The Ruins of Earth" shelved `anthology, sci-fi`) and are consumed into
  `Work.literary_form` instead of becoming a redundant `Tag`/`Genre`.
  Deliberately *not* extended to the many other subject-area labels that
  are also very likely nonfiction (`biography`, `philosophy`, `science`,
  `business`, ...): several of them (`ai`, `futurism`, `politics`,
  `psychology`, `astronomy`, `culture`) are exactly the kind of theme a
  genuine SF *novel* explores too, so inferring `literary_form:
  nonfiction` from a
  subject tag risks silently mis-typing a real novel — a materially
  different risk from the three structural labels above, which describe
  the book's form, not its subject. Everything else still defaults to
  `novel`, hand-correct per `PHILOSOPHY.md` principle 6 where it matters.
  Confirmed against the real run: 18 `anthology`, 5 `collection`, 2
  `essay`, 1,949 `novel` (down from 1,974 before this distinction was
  drawn), zero redundant `anthology`/`collection`/`essays` Tags left
  behind.
- **Genre seeding from Thema (principle 9), done in `db/seeds.rb`** —
  fetched directly from EDItEUR's own Thema code list
  (`ns.editeur.org/thema/en/FL`, `/FM`), not reconstructed from memory:
  the FL (Science fiction) tree, plus FM (Fantasy) as a deliberate small
  extension beyond `DATA_MODEL.md`'s literal "FL" wording (this
  collection has real fantasy books — 15 shelved `fantasy` in the real
  export). `bisac_code` is only set on the two top-level rows
  (`FIC028000`/`FIC009000`, confirmed against BISG's own list directly);
  left blank on sub-codes rather than guessed. The importer's
  `goodreads:import` rake task now runs `db:seed` itself before
  importing — not just documented as a manual prerequisite — because
  skipping it silently changes results (every label reclassifies as a
  `Tag` instead) in a way that's easy to forget when this gets
  productionized. One real matching gap seeding alone didn't close:
  Goodreads' informal `sci-fi` shelf label (661 real books) never
  matches Thema's official `Science fiction` name by case-insensitive
  string comparison — bridged with a small alias table
  (`RowParser::GENRE_ALIASES`) rather than renaming the seeded Genre to
  the informal spelling, which would have defeated the point of using
  the standard's real vocabulary. `fantasy` needed no alias — it already
  matches Thema's `Fantasy` directly. Confirmed against the real run:
  659 `Work`s classified `Science fiction`, 15 `Fantasy`.
- **`Subject` (Dewey-flavored, shallow, curated)** — added alongside
  Genre/Tag once deepening the *fiction*-side tagging (to match the
  richer trope/theme vocabulary used on published reviews — see
  `DATA_MODEL.md`'s "Genre / Subject / Tag" section for the full
  reasoning) made the collision risk in the previous "27 personal labels
  correctly still Tags" line real rather than hypothetical: a `Tag`
  meaning "this SF novel explores politics as a theme" and a `Tag`
  meaning "this nonfiction book is about politics" would have been
  indistinguishable strings in the same table. `link_shelves` now tries
  Genre, then `Subject` (via `RowParser::SUBJECT_ALIASES` — only `ai` ->
  `Artificial intelligence` needed one), before falling back to `Tag`.
  Every fiction `Work` also gets a single shared `Subject` "Fiction" row
  structurally (`Goodreads::Importer#ensure_fiction_subject`), applied
  from `literary_form` rather than matched from a shelf label — mirroring
  how most public libraries don't apply Dewey to fiction at all. That
  default only applies when no *other* Subject already matched (a real
  nonfiction topic match, e.g. "SPQR: A History of Ancient Rome" ->
  `History`, wins over the default — a Work can't honestly be both).
  Bounded, disclosed gap: a genuinely nonfiction book with no recognized
  subject tag *and* a defaulted `literary_form` (still "novel", since
  Goodreads gives no reliable fiction/nonfiction signal) will incorrectly
  default to `Fiction` — hand-correct per principle 6, same as
  `literary_form`'s own default. Confirmed against the real run: 1,855
  `Work`s -> `Fiction`, the remaining ~24 real nonfiction topics
  correctly classified (`Business` 30, `Technology` 21, `Science` 16,
  ... down to `History`/`Travel`/`Futurism`/`Reference` at 1 each), zero
  `Tag`s left over, and exactly 2 Works (both `essay` `literary_form`,
  correctly excluded from the `Fiction` default) end up with no Subject
  at all — an honest gap, not a bug, since nothing in this curated list
  covers "literary criticism about SF."
- **Real author-field data quality issues in the export**, left as-is
  rather than auto-corrected: Goodreads slug artifacts as literal author
  names (`delany-samuel-r`, `wil-mccarthy`), and garbled joint-author
  fields (`"Larry & Jerry Niven & Pournelle"`, `"William;Sterling
  Gibson"`). Affects a small number of rows; auto-detecting these
  patterns risks misfiring on legitimately hyphenated or "&"-joined pen
  names, so they're left for manual `Contributor` cleanup rather than
  guessed at.
- `currently-reading`'s `date_started` uses `Date Added` as the best
  available proxy — extending the same reasoning Phase 2's RSS section
  below already gives for `user_date_added` (no field is a true "date
  started") to the CSV's equivalent column, which the doc didn't say
  explicitly for Phase 1.

## Phase 2: ongoing sync

### Self-contained, per `PHILOSOPHY.md` principle 20

A Solid Queue recurring job inside opsimath itself — not an external
aswarm/Rhai pipeline hitting opsimath over HTTP, even though that pattern
already works for librarium. Chosen deliberately over reusing the
existing pipelines as-is: principle 13 already argued against opsimath
depending on infrastructure outside its own control for scheduling, and
that reasoning applies exactly as well here. The *logic* from the
existing pipelines is ported into native Ruby; the *infrastructure*
(aswarm, Rhai, an external cron trigger) isn't.

One side effect of this choice: the Goodreads sync itself doesn't need
librarium's `LIBRARIUM_API_TOKEN`-style PAT mechanism, since it runs
inside the same Rails process and calls service-layer Ruby code directly
rather than POSTing to an external API (the same "CLI calls code, not
HTTP" pattern principle 18 already established). **An API token system
is still confirmed needed, though** — for other automation/integration
access (matching librarium's own PAT pattern, per that project's own
`internal/api/middleware/auth.go`), separate from the human `User`/
`Session` login. Built alongside Rails 8's auth generator as a small
`ApiToken` model (see `DATA_MODEL.md`'s `User`/`Session`/`ApiToken`
entry) rather than deferred — not because this phase's Goodreads sync
needs it directly, but because it's part of the same auth foundation and
confirmed as a real near-term need.

### RSS mechanics

`https://www.goodreads.com/review/list_rss/{GOODREADS_USER_ID}?shelf={SHELF}&key={GOODREADS_RSS_KEY}`
— confirmed working against the real account in the existing pipelines.
Needs the numeric user id (not the vanity username — 404s otherwise) and
the shelf RSS key, both credentials (Rails encrypted credentials, not
`.env` — no external pipeline process to configure this time). Per-item
fields available and already proven useful: `book_id`, `isbn`, `isbn13`,
`author_name`, `user_date_added`, `user_rating`, `user_review` (HTML),
`user_read_at` (read shelf only). **No field is a true "date started"** —
`user_date_added` (when shelved) is the best available proxy, same
conclusion the existing pipelines already reached.

### State tracking: `GoodreadsSyncState`

New — nothing in `DATA_MODEL.md` covered this before now. One row per
`(goodreads_book_id, shelf)`, holding the last-synced values needed to
detect a genuine change on the next poll:

| Field | Notes |
|---|---|
| `id` | |
| `goodreads_book_id` | Goodreads' own id — stable, always present in the feed |
| `shelf` | which shelf this state applies to |
| `last_synced_payload` | JSONB — shape depends on shelf (e.g. `{rating, review, date_finished}` for `read`; `{date_added}` for `currently-reading`), same flexible-payload pattern as `EnrichmentRecord`/`PendingDecision` rather than a fixed column set |
| `updated_at` | |

Critically: comparison is always against **this latest snapshot**, never
a permanent "have we ever seen this combination" set. The existing
`read-sync` pipeline's header comment documents exactly why the permanent
version is wrong — it can't handle a value *reverting* (an edited review
reverted, a reread landing back on a previously-seen rating), which would
be wrongly treated as "already handled." This table replaces that
pipeline's flat JSON snapshot files with a real table, same semantics.

**One batched lookup per shelf per run, not one per item.** Fetch all
~100 feed items first, then a single
`WHERE goodreads_book_id IN (...) AND shelf = ...` query against
`GoodreadsSyncState` for the whole batch, diffed in memory — not an
implicit per-item round-trip. This is the real efficiency gain available
here, and it's free (no assumption required, no correctness risk).

Deliberately *not* done: skipping ahead in the feed based on item order
(e.g., stopping once an already-seen, unchanged entry is hit). Rejected
even though it's tempting, for two reasons: the RSS fetch itself always
returns the same up-to-100 items regardless — Goodreads has no
"what's new since X" query, so this would only ever save the (already
trivial, ~100-rows-a-day) in-memory comparison work, never a network
call; and it depends on an unverified assumption — that Goodreads
reorders a shelf item when its *content* changes (a rating or review
edited after the fact), not only when it's newly shelved. None of the
existing pipelines rely on or document that assumption. If it turned out
false, an early-stop would silently miss a genuine edit sitting further
down the feed — a real correctness risk for a performance gain that's
already zero, since the fetch cost doesn't change either way.

### Matching strategy

Improved on the existing pipelines' title+author-only approach, made
possible by opsimath's `EditionIdentifier` bag: try an ISBN match first
(`isbn`/`isbn13` from the feed against `EditionIdentifier`), fall back to
the proven exact-title-plus-author disambiguation (normalized, series-
suffix stripped) when ISBN doesn't resolve — librarium's own comment notes
ISBN is "sparse" for older editions, not useless, so trying it first when
present is a free improvement, not a redesign.

### Per-shelf behavior

- **`wishlist`** → create/update a `WishlistItem` — and only a
  `WishlistItem`. To be explicit about something the first draft of this
  doc left ambiguous: `WishlistItem` holds its **own** denormalized
  `title`/`author_name` copy (already how it was designed — those fields
  are free text precisely because "the wanted book may not exist as a
  `Work` row yet"), not a reference to one. So a wishlist-shelf row from
  Goodreads does **not** create a `Work`/`Edition` — the book being wanted
  isn't added to the actual catalog at all, only to this separate,
  lightweight "things I want" list. `work_id` stays null unless/until the
  book is later matched to something already genuinely cataloged for an
  unrelated reason (e.g. you already own a different edition).

  No existing pipeline precedent for this shelf (none of the three
  librarium pipelines watch it) — new design. When the RSS diff later
  shows the book has *left* the wishlist shelf (typically onto
  `to-read`), the normal `to-read` handling creates the real `Work`/
  `Edition`/`Copy` fresh from *that* shelf's own data (which will usually
  be more complete — an ISBN, for instance — than the wishlist entry
  ever had), and the `WishlistItem` is simply deleted rather than merged
  or converted — its job (tracking "I want this") is done once the
  `Copy` exists to say "I have this" instead. The diff itself is the
  lifecycle trigger; no separate status field on `WishlistItem` is
  needed.
- **`to-read`** → create `Work`/`Edition`/`Copy` if genuinely new (direct
  precedent: `goodreads-librarium-sync.yaml`). Per your stated convention,
  this is where a book becomes an owned copy.
- **`currently-reading`** → open a `Reading` (`status: reading`,
  `date_started` from `user_date_added`) — direct precedent
  (`-reading-sync`).
- **`read`** → close the matching open `Reading` (`status: completed`,
  `date_finished` from `user_read_at`, plus rating/review) or create one
  if none is open — direct precedent (`-read-sync`).
- **`did-not-finish`** → same shape as `read` but `status: dnf`, no rating
  expected. No existing pipeline precedent (librarium never synced this
  shelf) — new design, modeled on `-read-sync`'s proven shape.

**Auto-create policy: confirmed yes.** librarium's `read`/`reading`
pipelines never auto-create — an unmatched entry just alerts, on the
premise "this should already exist" (added via the `to-read` sync or by
hand). Opsimath is more liberal, deliberately: auto-create a minimal
`Work`/`Edition` from the feed's limited fields when nothing matches, then
flag it for enrichment, rather than just alerting. This is only viable
because `PendingDecision` gives opsimath a safety net librarium didn't
have at the time; genuinely ambiguous cases (multiple exact-title matches
that don't disambiguate, or an already-open `Reading` when
`currently-reading` fires again) still route to `PendingDecision` rather
than guessing.

### Ambiguous outcomes → `PendingDecision`

Every case the existing pipelines handled with a Discord alert becomes a
`PendingDecision` instead — actionable in-app, not just a notification:
`kind: unmatched_shelf_entry` (no confident match, review manually),
`kind: possible_duplicate_work` (matches more than one existing `Work`
ambiguously), and a new one this design surfaces —
`kind: reread_conflict` (a `currently-reading` event fires while a
`Reading` for that work is already open — genuinely ambiguous: duplicate
event, a forgotten-to-close previous read, or an intentional reread
starting before the last one's paperwork caught up).

Out-of-band notification (Discord or similar, matching the existing
pipelines' pattern) isn't built in this phase — the `PendingDecision`
queue is the v1 review mechanism. A notification layer on top is a
reasonable future nicety, not a requirement here.

## Explicitly out of scope for this phase

- Any UI. Verification happens via Rails console or, at most, a minimal
  read-only view — not a reason to design screens yet.
- Reverse sync (opsimath → Goodreads). Goodreads is the source of truth
  for now, deliberately, because it's what keeps your community/network
  presence in sync; inverting that is a real future direction, not this
  phase.
- Discord/notification layer on top of `PendingDecision`.
- Any `isfdb-adapter` API changes — use it as-is; revisit only on real
  friction.
