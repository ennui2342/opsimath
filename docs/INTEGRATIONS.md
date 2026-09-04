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
via `bin/rails isfdb:enrich_editions`). `IsfdbEnrichmentJob.perform_now(force:
true)` (`bin/rails isfdb:reenrich_editions`) re-fetches an edition even
when it already has an isfdb `EnrichmentRecord` — the ordinary task only
picks up editions no one's tried yet, so a change that only reaches an
edition on its next real fetch (a new field, or a looser apply rule like
`CoverApplier`'s `authoritative:` cover trust, 2026-09-04) needs the
forced sweep to actually reach the existing library rather than only
newly-catalogued editions. A few things only became clear by actually
building this and checking the live mirror directly (read-only queries
through the running adapter pod, not guessed):

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
  something changed. (2026-09-04: that normalization stripped `&` but
  not the word `and`, so `"Faber & Faber"` vs `"Faber and Faber"` still
  read as a conflict — `normalize_name` now collapses both connectors.
  A 3-PD tail on the prod backlog; the same gap would have kept
  recurring.) Of the remaining 521 substring-containing pairs, 442
  (85%) were plain generic-suffix variants (`"Tor Books"` vs `"Tor"`,
  `"DAW"` vs `"DAW Books"`) and 79 (15%) carried a territory qualifier
  (`"Orbit"` vs `"Orbit (US)"`, `"Roc"` vs `"Roc UK"`) that `PHILOSOPHY.md`
  principle 11 says matters for vintage SF collecting.

  First pass merged only the generic-suffix 442 and held the 79
  region-flavored ones back as real disputes — **revisited directly at
  Mark's prompt** ("is it reasonable to trust a more specific region
  specific publisher entry to override the general?"). On reflection
  that first pass conflated two different risks: since this is an
  ISBN-keyed lookup, a region qualifier ISFDB adds describes the *exact
  printing that ISBN identifies* — the same trust already extended to
  every other enriched field — not a competing guess about the
  collector's physical copy. The real risk was something else entirely:
  isfdb-adapter matching a *different* printing via a reused ISBN (its
  own documented caveat), which shows up as *multiple* fields disagreeing
  at once, not as an isolated region qualifier. Confirmed directly: of
  the 79 region-flavored pairs, 65 were isolated (nothing else disagreed
  on that edition) and 14 co-occurred with another genuine conflict. So
  region-flavored pairs are no longer special-cased as *disputes* — and
  what actually gates a merge is the multi-field check below, not whether
  the extra text looks like a territory marker.

  **Later correction (2026-09-02, prod pending decision 13 — `"Futura
  Orbit"` vs `"Orbit"`).** "Merge all substring variants toward the more
  complete form" over-reached in the other direction: one publisher name
  containing another is only *evidence* of sameness when the extra words
  carry no identifying information. `"Futura Orbit"` ⊃ `"Orbit"` by
  string containment, but "Futura" is a distinct imprint name (Futura's
  Orbit line, later Little, Brown's) — not a formatting or region
  difference — so assuming either the longer or the shorter form is
  correct is exactly the guess we shouldn't make. `plan_publisher` now
  takes the merge-toward-completeness path only when the difference
  between the two names carries no identifying information — one of:

  - the longer name is an imprint/parent form joined by `/` or `&`
    (`joined_imprint_form?`: `"Gollancz / Orion"`, `"Hodder &
    Stoughton"` — ISFDB's house style for writing an imprint with its
    lineage attached, trusted like a territory qualifier because the
    ISBN keys the exact printing; Mark, 2026-09-02: trust the fuller
    form);
  - the names differ *only* by a bracketed or comma-led qualifier tail
    (`qualifier_tail?`: `"Orbit"` vs `"Orbit (Hachette)"`, `"Arrow
    Books"` vs `"Arrow Books (London)"`, `"Berkley Books"` vs `"Berkley
    Books, New York"`) — always a territory / city / parent qualifier on
    an ISBN-keyed lookup;
  - every remaining extra token is in `NON_DISTINGUISHING_PUBLISHER_WORDS`
    — corporate form (`books`, `press`, `publishing`, `ltd`, `plc`,
    `inc`, `co`, `group`, `house`…), format/imprint line (`paperbacks`,
    `hardback`, `science`, `fiction`, `fantasy`, `sf`), or territory
    (`us`, `uk`, `canada`, `london`…).

  So `"Tor"` → `"Tor Books"` / `"Tor Science Fiction"`, `"Orbit"` →
  `"Orbit (US)"`, `"Gollancz"` → `"Gollancz / Orion"`, `"Bloomsbury"` →
  `"Bloomsbury Publishing PLC"` all still merge; `"Orbit"` vs `"Futura
  Orbit"`, `"Granada"` vs `"Panther Granada"`, `"Gollancz"` vs `"Victor
  Gollancz"` (either direction) are now normal `enrichment_conflict`s and
  show up as a selectable field on the review screen. The multi-field
  bundling below still applies on top — a would-be-safe merge that
  co-occurs with a genuine conflict is held back regardless.

  **Retroactive sweep (2026-09-02, `script/publisher_sweep.rb`).** The
  heuristic change was applied back over the existing backlog, since the
  old rule had both silently dropped disagreements (catalog held the
  longer name, nothing else conflicted → `:unchanged`, no decision) and
  silently overwritten the catalog publisher with ISFDB's form
  (`field_sources["publisher"]` → `"isfdb"`, no review). Over 1,459
  ISFDB-enriched editions the sweep: (1) restored publisher +
  field-source from the pre-ISFDB source on the 24 editions where ISFDB
  had silently overwritten with a form the new rule counts as distinct
  (`"Spectra"` → `"Bantam Spectra"`, `"Griffin"` → `"St. Martin's
  Griffin"`), so step 3 raises a proper review decision for them;
  (2) deleted all 379 pending `source=isfdb` `enrichment_conflict`
  decisions (none had ever been resolved and the model carries no
  partial-review state, so this cost only row ids); (3) re-ran
  `IsfdbEditionEnricher.reprocess` over every ISFDB `EnrichmentRecord`,
  which regenerated those decisions under the new rule, auto-applied 25
  now-safe refinements (`"DAW"` → `"DAW Books"`, `"Gollancz"` →
  `"Gollancz / Orion"`), and raised ~11 new publisher conflicts
  (`"Victor Gollancz"` vs `"Gollancz"`, `"Panther Granada"` vs
  `"Granada"`, a `"Hardwired"`/`"Wired"` pair that looks like bad source
  data) that the old rule had swallowed. Joined-name and qualifier-tail
  forms ISFDB had already applied were left as-is — the new rule agrees
  with them.
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
- **`format` — the same "don't fabricate a value" fix, caught while
  building Phase 2, fixed retroactively in Phase 1's already-imported
  data too (2026-08-05).** Mark caught this directly while reviewing the
  Phase 2 plan: Phase 2's RSS feed has no binding/format field at all
  (not even an "Unknown" value — a real absence, not just an unhelpful
  one), and defaulting to `"paperback"` there would fabricate data and
  manufacture avoidable `PendingDecision`s that ISFDB enrichment could
  otherwise have filled in cleanly with no conflict — the same
  false-precision problem `publish_date`'s EDTF fix already solved for
  dates. Checked how far this already applied to Phase 1's *existing*
  CSV-imported data before fixing it: only 10 of the 1,985 real catalog
  rows ever had a genuinely blank/`Unknown Binding` `Binding` value
  (`RowParser.format_and_detail`'s fallback only ever fired for these
  10 — the other 1,798 `"paperback"` values came from a real Goodreads
  `Binding` string, not a guess). Of those 10 real `Edition`s, 2 had
  already been ISFDB-matched and, in both cases, ISFDB's real answer
  happened to also be paperback — coincidentally correct, but never
  actually verified until this fix reprocessed them; the rest either
  hadn't been ISFDB-matched yet or have no ISBN at all and never will
  be.
  Fixed: `Edition.format` is now nullable (`allow_nil`, not
  `presence: true` — same shape as `publish_date`'s own validation);
  `RowParser.format_and_detail` returns `[nil, nil]` for a genuinely
  blank/`Unknown Binding` value instead of guessing paperback; the 10
  affected `Edition`s had their fabricated `format` cleared and were
  reprocessed against ISFDB directly (no new HTTP call needed — the
  `EnrichmentRecord`'s stored `raw_payload` already had the real
  answer). Phase 2's auto-create path (see below) follows the same
  policy from the start: leaves `format` blank when Goodreads gives no
  signal, never fabricates a default. Audited both phases for the same
  shape of problem right after (2026-08-05, prompted by Mark): the one
  other candidate, a real-but-*unrecognized* `Binding` string (e.g. some
  hypothetical "Board book" — not in `FORMAT_BY_BINDING` but not blank
  either) also fell back to a guessed `"paperback"`, though 0 real rows
  in the actual export currently hit that path. Fixed the same way for
  consistency — `format_and_detail` never fabricates a value regardless
  of input now, only ever a real mapped value or `nil`. (`literary_form`'s
  own `"novel"` default was audited too and deliberately left as-is: it's
  already visibly documented as a default-and-hand-correct convention,
  and unlike `format`, ISFDB has no work-type data at all to clean it up
  automatically later — nullable would just mean permanently blank
  rather than usually-right.)

**A new `PendingDecision` kind, `enrichment_edition_mismatch`, for when
*multiple* fields disagree on the same edition at once.** Checking this
directly (grouping the 688 conflicts by `entity_id`) found 97 editions
with two simultaneous disagreements — sampled several, and every one
showed a different publisher *and* a multi-year date gap together (e.g.
"A Storm of Swords 2": `HarperVoyager ` vs `Harper Voyager (UK)`
*and* `2011` vs `2016-12`). That's isfdb-adapter's reused-ISBN caveat
made concrete: not two independent disputed facts, but one real
question — "does this ISBN match the right printing at all" — which is
categorically different from "which value is correct for this one
field." Splitting it further by year-gap size also surfaced one genuine
outlier: a book with `current_value: "1825"` vs proposed `"2013-09-12"`
turned out to be a Goodreads data-entry typo, not an ISFDB mismatch —
confirming that isolated single-field disputes and multi-field
disagreements really are different phenomena with different likely
causes, not just "more of the same."

`Enrichment::IsfdbEditionEnricher#apply_fields` now plans every
candidate field before committing any of them (via `Enrichment::FieldApplier
.plan`/`.commit`, split out for exactly this — `.commit` has since moved
to the shared `Enrichment::SourceRecorder` introduced in the Phase 3
addendum below, `FieldApplier` itself is plan-only now), rather than
deciding field-by-field as it goes. Plain fills are always
committed immediately — they can't discard anything regardless of which
printing the data actually describes. Fields needing an actual judgment
call (a refinement *or* a conflict) are counted together: with at most
one, it's trusted exactly as before (an isolated refinement applies, an
isolated dispute raises one normal `enrichment_field_conflict`); with a
genuine conflict alongside anything else needing judgment — another
conflict, or even an otherwise-safe-looking refinement — none of them
are committed individually. They're bundled into one
`enrichment_edition_mismatch` `PendingDecision` instead, since the
co-occurrence itself is evidence the *refinement* might also be
describing the wrong printing, not just the conflicting field. Two
refinements with no real disagreement between them are *not* bundled —
only a genuine conflict triggers holding the rest back too.

**Numbers from dev at the time** (post-EDTF-fix, post-publisher/
page_count fixes, post-multi-field-bundling, all via `IsfdbEditionEnricher
.reprocess` against already-stored `raw_payload` — no new network calls
for any of it): total pending decisions 2,705 -> 526 (432
`enrichment_field_conflict`: 213 `publish_date`, 214 `publisher`, 5
`format`; 94 `enrichment_edition_mismatch`, every one bundling exactly 2
fields in this dataset).

**Correction, found deploying to production (2026-08-05): that 526/94/432
split is a stale historical artifact, not the number the current code
actually produces.** Dev's `Edition`s were enriched across three
incremental rounds *while the bundling mechanism itself was still being
built* — some editions had one field (e.g. `publish_date`) already fixed
by an earlier round before the bundling logic existed, so a genuine
original two-field disagreement now only shows one remaining dispute in
dev, correctly isolated rather than bundled, simply because the other
field isn't in dispute *anymore*. Confirmed directly: reprocessing every
dev `Edition` against its own already-stored ISFDB payload (rolled back,
no real change made) moved the bundled count from 94 to 188 — proof the
92-bundle gap was staleness, not a real difference in the underlying
data. Production ran the complete, final code once, from a blank
database, in a single pass — every genuine multi-field disagreement got
bundled correctly from the start, nothing masked by earlier partial
fixes. **Production's split is the trustworthy one**: 530 total (340
`enrichment_edition_mismatch`, 190 `enrichment_field_conflict`) — treat
this, not dev's 526/94/432, as what the current code actually produces.
The near-equal *totals* (526 vs. 530) are what made this easy to miss —
the *kind* split is what actually diverged.

Reviewing what's left is real, separate follow-up work with no UI to do
it through yet — not a defect in this job, and every remaining number
has a specific, checked reason behind it rather than being an
unexamined pile.

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
— confirmed working against the real account in the existing pipelines,
and again directly against the live feed before writing any Phase 2 code
(2026-08-05, per Mark's explicit instruction — see below). Needs the
numeric user id (not the vanity username — 404s otherwise) and the shelf
RSS key, both credentials (Rails encrypted credentials, not `.env` — no
external pipeline process to configure this time).

**Real per-item field list, confirmed against the live feed, not
assumed**: `book_id`, `title`, `author_name` (primary author only, a
single string — no equivalent of the CSV's `Additional Authors`),
`isbn`, `book_published` (year only), `book_description` (a real
synopsis, unlike ISFDB's — see the enrichment addendum below),
`num_pages` (nested under a nested `<book id="...">` element, not a
flat tag), `user_rating` (0 = unrated, same convention as the CSV),
`user_review` (HTML, with literal `<br />` tags), `user_read_at` (read/
did-not-finish shelves only), `user_date_added`, `user_date_created`,
`user_shelves` (comma-separated when a book carries more than one
shelf — same shape as the CSV's `Bookshelves`). **`isbn13` does not
exist in this feed at all** — only `isbn` (always a real ISBN10,
confirmed across all 291 non-blank values across all 5 shelves in a
live pull). An earlier draft of this doc assumed both were available;
matching against the feed must key off `EditionIdentifier(id_type:
"isbn10")` only. **No binding/format field exists either** — Phase 2's
auto-create path leaves `Edition.format` blank rather than guessing, see
the Phase 0 fix note below. **`num_pages` *is* present in the feed, but
`ShelfSync` deliberately never reads it into `Edition.page_count`** —
consistent with Phase 1's own call above (dropping Goodreads'
`Number of Pages` from the CSV import entirely, since it disagreed with
ISFDB often enough and matters little enough to a collector to trust as
a baseline), not an oversight specific to Phase 2. Left to ISFDB
enrichment to fill in, same as the CSV path.

**No field is a true "date started"** — `user_date_added` (the shelf's
most recent transition date, not `user_date_created`, which is the
original first-ever-shelved date and can be much earlier) is the best
available proxy, same conclusion the existing pipelines already reached.
Double-checked directly against a real to-read → currently-reading
transition (*The Solaris Book of New Science Fiction*: `user_date_created`
2026-01-30 = when first added to any shelf; `user_date_added` 2026-07-28
= the actual move to currently-reading) before trusting this, since an
earlier pass in this same session suspected the doc had it backwards —
it didn't.

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

The title+author fallback resolves a *work*, not an *edition*: today
`Matcher` returns `work.editions.first`, which is arbitrary the moment
you own more than one edition of a book. That gap, and the related "you
changed which edition a book points at on Goodreads" case, are handled
by the edition-reconciliation addendum below — not by guessing here.

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
- **`currently-reading`** → **gets the same auto-create-if-unmatched
  behavior as `to-read`, not just "open a Reading against an existing
  match"** — a real, caught-live example: a magazine issue (*Clarkesworld
  Magazine, Issue 238*) arrived in the post and was started the same day,
  entering the feed via `currently-reading` with no prior `to-read`/
  `wishlist` history at all. An earlier draft of this doc only described
  `currently-reading` as opening a `Reading` against an already-known
  book — real usage shows a book can enter the library for the first time
  through *any* status shelf, not just `to-read`. So: auto-create if
  `Matcher` finds nothing, then open a `Reading` (`status: reading`,
  `date_started` from `user_date_added`) on the fresh `Edition` — direct
  precedent for the "open a Reading" half (`-reading-sync`), new for the
  auto-create half.
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

**`book_published` is the work's original publication year, not this
edition's — confirmed empirically, not assumed.** A live RSS fetch (226
real items across `read`/`currently-reading`/`to-read`) cross-referenced
against the local CSV export by `book_id` found `book_published` matches
CSV's `Original Publication Year` in 209/209 (100%) of cases and CSV's
edition-specific `Year Published` in only 58/207 (28%) — e.g. real
Neuromancer, book_id 953070: CSV `Year Published` 1993 (the actual
edition Mark shelved), CSV `Original Publication Year` 1984, RSS
`book_published` 1984. The CSV importer already reads two genuinely
separate Goodreads columns for this; the RSS feed only ever exposes the
work-level one. `create_work_and_edition` used to apply it to both
`Work.original_publication_year` (correct) and `Edition.publish_date`
(wrong) — the same false-precision shape `PHILOSOPHY.md` already flags
elsewhere (the `publish_date` EDTF fix, the `format` fabrication fix).
Fixed: `Edition.publish_date` is left blank for an RSS-auto-created
edition now, same as `format`/`publisher` already were, for ISFDB
enrichment to fill in properly. Real consequence worth knowing: since
this was the *only* Edition field `create_work_and_edition` ever
pre-populated, a freshly auto-created edition now starts with every
enrichable field genuinely blank — its first ISFDB pass can only ever be
a clean fill, never a spurious conflict.

**`num_pages`** is available in the RSS feed (`book/num_pages`) and
confirmed edition-reliable (100% match against CSV's own `Number of
Pages` for the same book, 213/213) — but deliberately still not used,
per the existing `page_count` policy above: Mark's call is that
Goodreads' page count is untrustworthy against ISFDB regardless of
source, not worth the conflicts it would generate.

**Cover images**: the RSS feed carries `book_image_url` (and 3 smaller
variants — `book_image_url`/`book_small_image_url` are both the same
~75px thumbnail; `book_large_image_url` is the only genuinely full-size
one) — previously unused entirely. `create_work_and_edition` now
downloads and attaches it the same way `IsfdbEditionEnricher` does for
its own cover fills — a plain fill, not staged as a candidate (nothing
to compare against yet on a just-created edition). A later ISFDB pass
still runs its own checksum comparison against whatever's already
attached, same as any other Goodreads-sourced field.

**Goodreads is a peer enrichment source, not the library's source of
truth — the root cause behind both fixes above.** Both the `book_published`
mislabeling and the cover-comparison false-conflict regression traced
back to the same thing: `Importer#create_edition`/`ShelfSync#create_
work_and_edition` wrote straight onto `Edition` columns at creation time,
with no comparison logic and no durable record of what Goodreads
actually claimed — unlike ISFDB, which already went through a real
fill/conflict pipeline (`Enrichment::FieldApplier`). Fixed by routing
Goodreads through that same pipeline via a new `Enrichment::SourceRecorder`,
which both import paths now call instead of writing columns directly.
Observably identical today for a genuinely new edition (every field
starts blank, so every proposal is a clean `:fill` regardless of
source), but two real gaps close: a `goodreads`-provider `EnrichmentRecord`
now exists for every imported/synced edition (previously only ISFDB
created these), and Goodreads-derived text fields get `field_sources`
tagged (previously only `cover_image` was tracked at all). `EnrichmentRecord`
gained a `fields` jsonb column (populated by both providers, kept
separate from `raw_payload`) so a real side-by-side comparison across
sources is directly queryable from the database with no active
`PendingDecision` required — not just derivable from a raw fetch blob.
`PendingDecision.payload` was simplified to match: a thin pointer
(`{entity_type, entity_id, fields: [...], source}`) rather than a frozen
current/proposed snapshot, since freezing a value at raise time is a
real staleness hazard against a review backlog that can sit for months —
`PendingDecision#field_diffs` now derives the comparison live instead.

**A standalone magazine issue is a real auto-create case, distinct from a
novel or an anthology** — the same *Clarkesworld* example above. No
magazine ever appeared in the Phase 1 CSV export, so this never came up
until Phase 2's live feed surfaced it. `Work.literary_form` gained a
`periodical` value (alongside `novel`/`novella`/`short_story`/
`collection`/`anthology`/`nonfiction`/`essay`) — a magazine issue is a
genuinely different structural type (MARC/ONIX both distinguish serial/
continuing resources from monographs), not well served by defaulting to
`novel` or overloading `anthology`. Detected the same way `anthology`/
`collection`/`essay` already are: a `magazine`/`periodical` shelf tag, or
(new, since Goodreads gives no shelf-tag signal for a book it's never
seen shelved before) the title itself containing "Magazine" — confirmed
against the real example. Defaults to `novel` and hand-corrects
otherwise when neither signal is present, same safety net every other
`literary_form` default already relies on.

### Ambiguous outcomes → `PendingDecision`

Every case the existing pipelines handled with a Discord alert becomes a
`PendingDecision` instead — actionable in-app, not just a notification:
`kind: unmatched_shelf_entry` (no confident match, review manually),
`kind: possible_duplicate_work` (matches more than one existing `Work`
ambiguously), and a new one this design surfaces —
`kind: reread_conflict` (a `currently-reading` event fires for an edition
that *already has a completed `Reading`* and none open — genuinely
ambiguous: deliberate reread, a misclick, or a stale shelf status
resurfacing on a resync, with no date on the item to tell them apart.
Scoped to the matched edition, not the work — 2026-09-04: a
`currently-reading` event landing on an edition with no reading of its
own is an unambiguous new read, even when another edition of the same
work was read before, so `ShelfSync#currently_reading` just opens the
`Reading`. This is the common shape after an `edition_reconciliation`
`change_edition`: read the old printing, acquired and started a new one.)

### Addendum: edition-level reconciliation

The matching strategy above has a gap that only shows once you own more
than one edition of a book, or change which edition a shelved book points
at on Goodreads. `Matcher`'s title+author fallback returns
`work.editions.first` — arbitrary — and `ShelfSync`, on any work-level
match, does nothing but `record_goodreads_cover`: it never re-reads a
matched edition's ISBN/format/publisher from the feed (deliberate — the
RSS feed's per-edition data is thin and untrusted). So an edition swap on
Goodreads surfaces in opsimath as a lone `cover_image` conflict, which
reads as "only the cover differs" when in fact the catalogued edition is
now the wrong printing.

Real cases that exposed this (2026-09):
- **Facets** — re-shelved to a Tor US edition; the feed carried isbn
  `0812501810`, the catalogued edition has `0586213872` (Grafton UK). The
  ISBN delta is a clean "different edition" signal, sitting unused in the
  `goodreads` `EnrichmentRecord`'s raw payload.
- **The Anubis Gates** — re-shelved to a Goodreads edition with no ISBN
  at all. No clean signal — genuinely a human call whether it's a swap, a
  Goodreads id merge, or an added copy. Reread detection can't help
  disambiguate either: it keys on `goodreads_book_id` + read dates, and a
  dateless reread of the same work is already collapsed into the existing
  `Reading` regardless.

Built (2026-09): when `Matcher` resolves to a `Work` you own but not to a
specific `Edition` via `goodreads_book_id` (`by_title_author` now returns
`edition: nil` rather than `editions.first`), `ShelfSync#ensure_cataloged`
raises a `PendingDecision` of `kind: edition_reconciliation`
(`docs/DATA_MODEL.md`) and bails the shelf handler, same shape as
`possible_duplicate_work`. **Every** title+author match raises one —
nothing is handled silently; `relink` ("same edition, Goodreads churned
the id") is a one-click resolution. The question isn't "which field
value is right" but "how does this record map onto my editions and
copies", and the resolutions are structural: `relink` / `change_edition`
/ `add_edition` / `unowned_read` / `rejected`, applied by
`Goodreads::EditionReconciliationResolver` — still its own service class
even though it's a `kind` sharing `PendingDecision`'s queue/nav/index now,
not a separate model (2026-09-04 correction: originally built as its own
`EditionReconciliation` model/controller/nav item; reconsidered — same
underlying "a sync run flags something for a human" mechanism as every
other kind, worth one queue rather than two).

`relink` / `change_edition` / `add_edition` make the `goodreads_book_id`
resolve to a confident `Edition`, then **replay** the feed event through
`ShelfSync.sync` — the existing `read_like` semantics then open the
deferred `Reading` (a matching prior read date re-touches it in place; a
new date is a new reading on the confident edition). `unowned_read` is
handled directly: a `Copy`-less `Edition` (`Goodreads::EditionBuilder`,
the shared "build one Edition from a feed item" path, no `Copy`) plus a
`Reading` with `source: library`/`borrowed`/`other`. `change_edition`
first flips the replaced copy to `Copy(disposition: "replaced")`.

Two model deltas came with it:
- `Copy.disposition` gained `replaced` — `change_edition` ends the old
  copy without deleting it, so the `Reading` done in it keeps a real
  `Edition` to point at.
- The sync now creates a `Copy`-less `Edition` for `unowned_read`, and
  populates `Reading.source` (`ShelfSync` + `Importer` auto-creates
  default to `owned_copy`; the migration backfilled every existing
  `Reading` to `owned_copy`). Before this it always created an owned
  `Copy` for a `read`-shelf book and never set `source`, so opsimath
  over-claimed ownership for any library/subscription-ebook read shelved
  as read on Goodreads. Since the user is a physical collector (read ≈
  owned the large majority of the time), the auto-create default stays
  `owned_copy`; `unowned_read` is the escape hatch, not a flip of the
  default.

Reading stays bound to the edition it happened in — `change_edition`
never moves a historical `Reading`; a reread in a new edition is a new
`Reading`. `book_published` is still work-level (see above), so a
`change_edition`/`add_edition` `Edition` starts with every enrichable
field blank and takes its real values from the ISFDB pass on the new
ISBN — no fabricated edition data from the feed.

### Out-of-band notification: `Notifications::`

Built the same day the RSS sync itself went live, at Mark's request —
an earlier draft of this doc said out-of-band notification "isn't built
in this phase... a reasonable future nicety, not a requirement here."
That held only until the sync was actually running against a live
account: without it, "did the last hourly run do anything unexpected"
meant opening a Rails console, exactly the friction principle 20 already
argues against. `PendingDecision` remains the actionable, in-app review
queue — notification is purely a visibility layer on top, not a
replacement for it.

`app/services/notifications.rb` + `app/services/notifications/` — a
small, deliberately generic subsystem (`Notifications.notify(event)`,
one `LogNotifier` always active, one `DiscordNotifier` that joins when a
Discord bot token credential is configured), *not* Goodreads-specific,
so any future job can reuse it. Posts via the Discord bot REST API
(`POST /channels/{id}/messages`, `Authorization: Bot {token}`) using the
real bot token/channel id the existing `~/projects/aswarm` Goodreads
pipelines already use (`DISCORD_BOT_TOKEN`/`DISCORD_CHANNEL_ID` in that
project's `.env`) — the same mechanism their own `discord.py` connector
wraps, not a separate incoming webhook.

`GoodreadsSyncJob` is the only place this feature calls it — deliberately
not `Syncer`/`ShelfSync`, which stay pure/testable. Per event, one
message each: `auto_created` (a new Work/Edition/WishlistItem), a
`pending_decision` alert for each `reread_conflict`/
`possible_duplicate_work` `ShelfSync` raises, and `sync_error` if the run
itself blows up (re-raised after notifying, so Solid Queue's own retry/
failure tracking isn't short-circuited). `notify_summary`/`sync_summary`
existed here too until 2026-08-19 — see the correction below.

**Two follow-up fixes, both from real usage in production, not
speculative polish:**

- **`sync_summary` only fires when something was actually synced.**
  Originally sent every hour regardless — once the recurring job was
  genuinely live, an all-zero "synced=0, unchanged=327" message every
  single hour was pure noise (anything worth knowing already gets its
  own `auto_created`/`pending_decision` alert). `notify_summary` now
  returns early when `counts.synced` is zero.
- **The ISFDB-conflict `pending_decision` alert originally had no real
  content** — just the bare `kind` name plus an opaque `edition_id`/
  `pending_decision_id`, nothing to judge from a phone notification
  alone. Fixed to pull the book title (via `Edition.works`) and the
  actual disputed field(s) with their current → proposed values
  straight out of the `PendingDecision`'s own payload — see
  `PendingDecision#field_diffs` (`docs/DATA_MODEL.md`'s `PendingDecision`
  entry) for the live current-vs-proposed derivation this reads. (At the
  time of this fix, the payload was built by two separately-named
  methods, `FieldApplier#find_or_create_conflict`/`IsfdbEditionEnricher
  #create_edition_mismatch` — both since replaced by the unified
  `Enrichment::SourceRecorder.create_bundled_decision`, see the Phase 3
  addendum below.)

**A newly auto-created `Edition` also gets ISFDB enrichment triggered
immediately, scoped to just that one `Edition`** — a deliberate design
choice to satisfy "notify on the Goodreads updater's own activity"
without flooding Discord: this is a *separate, per-item* call, not a
hook into the existing bulk `IsfdbEnrichmentJob`/`isfdb:enrich_editions`
rake task, which stays completely untouched and silent (a full-library
run would otherwise generate hundreds of messages). Any conflict this
per-item enrichment raises gets its own `pending_decision` notification,
same as `ShelfSync`'s own.

**Every touched shelf item now gets a book-level notification, not just
genuinely new books.** Real gap Mark caught directly: an hourly run
reported "synced=1" with no individual message — the sync had picked up
a single new wishlist addition, which `auto_created` never covered
(`ShelfSync#wishlist` never creates a `Work`/`Edition`, so the old
`touched.created && touched.edition` gate silently excluded it, and
every other "already-known-book" shelf event — a to-read mark on a book
already in the catalog, a currently-reading start, a finished/DNF read —
was equally silent). `GoodreadsSyncJob::SHELF_TITLES` gives every shelf
its own verb (`"Marked to-read"`, `"Started reading"`, `"Finished
reading"`, `"Did not finish"`, `"Added to wishlist"`); `"Added to
catalog"` still wins over the shelf-specific wording whenever this is
the item's genuine first appearance in the library (`touched.created`),
since that's the more significant fact regardless of which shelf
triggered it — wishlist is the one exception, since it never creates a
`Work`/`Edition`/`Copy` even when `touched.created` happens to be true.

**Found and fixed in the same pass: the `PendingDecision.payload`
thin-pointer redesign (see `DATA_MODEL.md`'s `EnrichmentRecord`/
`PendingDecision` sections) had silently broken `conflict_summary`.**
It still parsed the old flat shape (`payload["current_value"]`/
`["proposed"]`), which no longer exists — `payload["fields"]` is now a
plain array of field-name strings, so every lookup silently returned
`nil` instead of raising, producing a garbage Discord message body with
no real field/value content. No test caught it, since nothing in the
freshly-auto-created-edition path this method is reachable from can
actually raise a text-field conflict (every field starts blank, and
`FieldApplier.plan` only ever returns `:conflict`/`:refine` for an
already-non-blank current value) — a real, if currently unreachable,
landmine rather than an active bug. Fixed to read
`PendingDecision#field_diffs` (the same live-deriving method the review
UI itself uses) instead of hand-parsing the payload.

**Two more real bugs, both found live during a cold-start resync
(every `GoodreadsSyncState` wiped for a demo, 2026-08-08) — `touched`
(Syncer's "no matching sync-state row, so this needs processing" signal)
had been conflated with `changed` (a real database write happened) ever
since the previous fix above, and the conflation ran deeper than that one
fix caught:**

- **Every shelf branch was notifying on `touched` alone, not just the
  wishlist gap already fixed.** A re-touch of an already-fully-known item
  (the overwhelmingly common case right after a state reset) is `touched`
  but made zero real writes — yet still notified "Added to wishlist"/
  "Started reading"/etc. for books that had been there for ages. Added an
  explicit `changed` field to `ShelfSync::Outcome`, computed correctly per
  branch (a pure re-match with nothing to remove is `changed: false`; a
  genuine wishlist→catalog transition, a newly-opened `Reading`, or a
  `Reading` whose values actually differ from what's already saved is
  `changed: true`), and gated every notification on it instead of on
  `touched`. Caught alongside it: a real duplicate-`Reading` bug from the
  same conflation — fixed as part of the same pass, see
  `Goodreads::ShelfSync`'s own test suite for the specific cases.
- **`sync_summary`'s `synced`/`unchanged` fields are Syncer's own
  bookkeeping (did an item have no matching sync-state row at all) —
  Mark caught immediately after the fix above that this reads as "N real
  changes happened" when it isn't one.** Right after a state reset,
  `synced=327, unchanged=0` looked like 327 real changes when only ~20
  genuinely were. Added a `changed` count (`touched.count(&:changed)`,
  the same field the per-item fix above introduced) alongside the
  existing fields rather than replacing them — `synced`/`unchanged` stay
  meaningful for Syncer's own state-diffing question, `changed` answers
  the different, more useful "did anything real happen" question.

**Correction, 2026-08-19: `notify_summary`/the `sync_summary` event
removed entirely, not just gated.** Both fixes above assumed the
per-run summary was worth keeping once it only fired on real activity —
in practice Mark found it provided nothing actionable beyond a bare
processed-count and feed size, redundant with the real per-item
`auto_created`/`shelf_update`/`pending_decision` messages already
covering everything worth knowing. `GoodreadsSyncJob#perform` no longer
calls it; `counts` is still the job's own return value (useful to a
caller/test), just no longer posted to Discord.

## Phase 3: a real review UI, one shared enrichment pipeline, and image-based cover comparison

Built the same week Phase 2 went live, once a real backlog of
`PendingDecision`s made "review via Rails console" (this doc's own
original scope) untenable — see `docs/UI_PRINCIPLES.md` for the UI design
principles this follows. Three changes, landed together because each one
surfaced the next while building/using it for real.

### The review UI replaces "Rails console or a minimal read-only view"

A 3-card comparison per `PendingDecision` (`Ui::ComparisonCardComponent`):
the `Edition`'s current catalog state (with a `field_sources` chip per
field), a card per other provider with an `EnrichmentRecord` on file
(reference only, not actionable), and the proposing source's card
(checkboxes on every disputed field, all checked by default — accepting
as-is reproduces the old silent-auto-fill outcome, but a reviewer can now
see the whole fetch, cover included, and uncheck anything that looks like
it belongs to a different printing before accepting). Keyboard-first
accept/reject per `docs/UI_PRINCIPLES.md` principle 3, Turbo Streams for
the accept/reject → next-item loop per principle 4.

### One shared pipeline for every enrichment source, not three drifting implementations

Mark's own diagnosis, after several bugs in a row all traced back to the
same root cause: "a field conflict isn't just an addition conflict...
shouldn't [a change coming through the RSS] be seen as an enrichment
change just the same? ... there's just this kind of separate treatment
of the Goodreads changes from the ISFDB changes... this false splitting
of the code is having great problems keeping any changes in sync."
Concretely true at the time: `Goodreads::Importer` had its own naive
apply loop, `Goodreads::ShelfSync` had a bolted-on cover-only call, and
`Enrichment::IsfdbEditionEnricher` had its own bundle-or-commit
orchestration — three separately-maintained implementations of "what to
do with a source's proposed fields," which is exactly how a Goodreads
cover conflict and an ISFDB cover conflict ended up producing two
differently-shaped `PendingDecision`s for no principled reason.

Fixed with one shared hub, `Enrichment::SourceRecorder` — every source
(Goodreads CSV import, Goodreads RSS sync, ISFDB enrichment) now routes
through the same `integrate` method to decide fill vs. bundle vs. hold,
and the same `commit_plan` to actually write a value. Per-field judgment
calls that are genuinely source-specific (ISFDB's publisher
substring-variant merging, its EDTF publish_date precision handling)
still live where they're informed by that source's real quirks — the
shared part is the *decision*, never field-specific planning logic that
has no reason to be shared. The bundling policy itself (established
earlier: the instant any field from a fetch is a genuine conflict,
*every* field that fetch proposed — fills and refinements too — gets
held back and offered together, since a blank destination field isn't
proof the fetch describes the same printing) now applies identically
regardless of source.

**`PendingDecision` kinds collapsed from two to one as a direct
consequence**: `enrichment_field_conflict`/`enrichment_edition_mismatch`
were never actually different in payload shape (both were already the
thin `{entity_type, entity_id, fields, source}` pointer from the earlier
redesign above) — they only ever differed in "one field name vs.
several," which isn't a different *kind* of decision, just a different
count. Both are now `enrichment_conflict`. See `DATA_MODEL.md`'s
`PendingDecision.kind`.

### Cover comparison: from byte-identical-only to real image similarity

Once Goodreads started proposing covers against ISFDB-populated editions
(and vice versa) under the shared pipeline above, byte-exact comparison
alone produced real false conflicts — the same physical cover, scanned/
photographed at different resolutions and crops by two different
providers, is never byte-identical even though a person looks at both and
immediately says "same cover." Explored pHash and ORB (feature-matching)
+ RANSAC; chose the latter after empirical validation against real
conflict pairs from the live backlog (including one ground-truth
self-correction — "Anathem" was initially read as a match on a quick
visual scan, caught by cross-checking against the system's own
independent conflict flag and then zooming into the blurb text, which
showed a genuinely different byline/typesetting).

New sidecar service, `services/cover_compare/` (Python/FastAPI,
`docker-compose.yml`'s `cover-compare` service) — deliberately a separate
service, not in-process Ruby, since OpenCV's Python bindings are the
mature option for this and the comparison is genuinely stateless/
cacheable work, not core application logic. Two real fixes needed once
validated against actual data, not just the algorithm choice:

- **Scale normalization.** ISFDB scans and Goodreads RSS thumbnails
  differ 3-8x in resolution, which alone drove the ORB match ratio down
  to misleadingly low values (0.003-0.008) even for genuinely identical
  covers. Fixed by resizing both images to a 600px canonical long side
  before matching.
- **A combined ratio + absolute-inlier-count threshold, not ratio
  alone.** A busy, detailed cover has a lot of keypoints regardless of
  how many actually match, so ratio (which divides by total keypoint
  count) can read low even on a confident match — a real spot-checked
  case scored 301 RANSAC inliers / 86% survival but still fell under a
  ratio-only threshold. `Enrichment::CoverApplier::MIN_INLIERS = 350`
  (alongside `SAME_THRESHOLD = 0.2`) sits between the two clusters
  actually observed post-normalization: every confirmed genuine match
  cleared 412+ inliers, the one confirmed genuine conflict in the same
  spot-check batch posted 277.

Wired into `Enrichment::CoverApplier.plan`: a populated destination with
bytes that differ from the proposed cover is no longer an automatic
conflict — the sidecar is asked first, and only a genuine visual
difference (or an unreachable sidecar) still raises one. Real effect on
a live batch: conflict volume for cover-only disputes dropped from ~28
to ~18 out of 228, spot-checked individually against the actual images
(12 correctly cleared, "The New Weird" correctly still flagged as a
genuinely different printing).

### `EnrichmentRecord` becomes one row per `(entity, provider)`, not one row per fetch

Full reasoning and the bug that surfaced it live in `PHILOSOPHY.md`
principle 10's correction and `DATA_MODEL.md`'s `EnrichmentRecord`
section — not repeated here. Two concrete Goodreads-side gaps this
closed, both real production data problems, not theoretical:

- **A CSV-imported (matched) edition never got a chance at a Goodreads
  cover at all.** The CSV export has no image URL column, and the RSS
  sync's cover-fill call only ever ran for a freshly auto-created
  edition, never a matched one — so an edition imported via CSV and later
  re-seen on an RSS shelf stayed coverless from Goodreads forever, even
  though the RSS feed had a real `book_image_url` for it every time.
  Fixed: `Goodreads::ShelfSync#ensure_cataloged`'s matched-edition branch
  now calls the same `record_goodreads_cover` (→ `SourceRecorder.record`)
  path the auto-create branch already used.
- **`Goodreads::Syncer#relevant_fields` didn't track `book_image_url` at
  all**, so a cover appearing in the RSS feed for an already-synced
  `(goodreads_book_id, shelf)` pair — exactly the backfill case above —
  never re-triggered `ShelfSync`, since `GoodreadsSyncState`'s diff saw
  nothing relevant had changed. Fixed: every non-wishlist shelf's
  `relevant_fields` now includes `book_image_url`, so a cover showing up
  where there wasn't one correctly re-triggers a sync pass and flows
  through the standard fill/conflict pipeline like any other enrichment
  change, per Mark's own framing ("a cover image appearing in the RSS
  feed where there wasn't one before means an update to the enrichment
  record, which then triggers an attempted sync to the edition — any
  update to the enrichment should flow into the standard match/conflict
  workflow").

### Addendum: a reused ISBN stops being a silent guess (`enrichment_printing_choice`)

An ISBN can name more than one ISFDB publication — a reissue keeps the
number (2026-08-10: 565 of 1,493 of the library's ISFDB-matched ISBNs hit
this). `IsfdbEditionEnricher` used to pick one: the candidate whose
publish year matched what was on file, else `candidates.first` (isfdb-
adapter's most-recent-first order). The fallback is a guess — and it
fires for *every* RSS-auto-created edition, which has no year on file
(`book_published` is Work-level, never written to `Edition.publish_date`).
Real miss (2026-09-03): The Anubis Gates edition 2032, ISBN `0586065504`
→ two ISFDB pubs (HarperCollins UK 1993 / Triad Grafton 1986); with no
year to disambiguate it took the 1993 one, wrong.

Now `#resolve_candidate` only auto-picks when it's *certain* — exactly one
candidate, or exactly one matching the known year. Anything else (no year
on file, year matches none, year matches several) raises a new
`PendingDecision` kind, **`enrichment_printing_choice`**: payload carries
the raw candidate list verbatim (accept never re-hits the adapter), and
`PendingDecision#printing_choice_cards` renders the Edition's current
state plus one `Ui::ComparisonCardComponent` per candidate printing —
each with a **radio in the header** ("this is the printing I own") *and*
per-field **checkboxes** inside, including the printing's cover as a real
`<img>` (every candidate's cover is downloaded server-side at raise time
into `PendingDecision#candidate_covers` — a `has_many_attached` keyed by
pub id — same as the `enrichment_conflict` flow, since ISFDB's own wiki
cover URLs Cloudflare-gate a browser hotlink).
`printing_choice_controller.js` keeps only the picked card's checkboxes
live. Accept
(`PendingDecisionResolver#accept_printing_choice` →
`IsfdbEditionEnricher.commit_choice`) writes exactly the checked fields
from the chosen printing straight onto the Edition — no `FieldApplier`
conflict gate, since the reviewer already made the "which printing, which
values" call in front of the full comparison. This is deliberately
*upstream* of the field-level `enrichment_conflict` bundling: pick the
right record first, then there's nothing left to dispute.

#### Addendum: most "reused ISBN" cases aren't ambiguous at all

Mark, looking at the real queue (2026-09-04): "the editions I'm choosing
between are often identical except maybe missing a field or two... they
seem to be the same record, just with better info rather than a different
printing." Confirmed by sweeping every pending `enrichment_printing_choice`
decision: **74%** had candidates agreeing on publisher, binding, and page
count, differing only in how completely each had been filled in — ISFDB
is a collaborative wiki, and independent contributors re-enter a printing
they already have on their own shelf rather than editing the existing
record. That's not a "which one do I own" question; it's ISFDB's own data
duplication being surfaced as if it were one.

`#resolve_candidate` gained a third tier, tried after the exact-candidate
and known-year cases and before giving up to a human: `#same_edition?`
treats every candidate as one real printing when they share the same raw
`binding` string, the same publisher once the existing
non-distinguishing-variant normalization (`#non_distinguishing_variant?`)
is applied pairwise, and page counts within `PAGE_COUNT_TOLERANCE` (10%
of the larger count) of each other. Mark on that last one: page count is
ambiguous to count on a collaborative wiki in the first place, a small
variance is almost certainly a counting difference between contributors
rather than a separate printing, and it's the least interesting field to
get right even on the rare occasion it does turn out to differ for real.
When every candidate clears that bar, `#richest_candidate` applies the
one that actually says the most — most precise `publish_date` first (the
string's own length is its precision, the same signal `#plan_publish_date`
already trusts), then whichever else has more of the fields this enricher
tracks filled in — rather than isfdb-adapter's own "most recent" default,
which has no bearing on which record is most *complete*.

This is a `resolve_candidate` change, so it takes effect automatically on
every future enrichment; it doesn't retroactively touch a decision
already sitting in the queue under the old, stricter rule. Those get
swept once via `bin/rails isfdb:resolve_duplicate_printings` — re-runs
`same_edition?` against each pending decision's already-stored candidates
(no new isfdb-adapter fetch) and auto-accepts (`PendingDecisionResolver.accept`,
same code path a human's own click would take) whichever now resolve,
leaving genuinely ambiguous ones exactly as they were. Side fix found
while wiring the sweep up: `accept_printing_choice`'s fallback field list
(used only when a caller doesn't pass `selected_fields` explicitly — the
real review form always does) was missing `cover_artist` — a decision
accepted programmatically with no explicit fields would silently never
apply it. Now reuses `PendingDecision::EDITION_FIELD_ORDER` directly
instead of a second, drifted-from-it copy of the same list.

### Addendum: reconciling an edition on demand, not just when something raised a conflict

The publisher-sweep analysis (2026-09-04) found the pending
`enrichment_conflict` backlog is 94% cover-image disagreements between
the Goodreads cover on file and the ISFDB one — a real, mostly-legitimate
backlog, not stale noise. Mark's response: he'd be more relaxed about
accepting an ISBN-matched ISFDB cover automatically (a policy for later)
if there were an easy, always-available way to fix the rare miss by hand
— not just when a `PendingDecision` happened to be raised.

**`EditionMetadataController`** (`/editions/:id/metadata`) is that: a
cog on every `Ui::EditionCardComponent` opens a comparison-review screen
for that edition — reference card plus one selectable card per
`EnrichmentRecord` source, *every* field pickable from *every* source
(mix cover from ISFDB with publisher kept as catalogued, say) — see
`docs/DESIGN_SYSTEM.md`'s `Ui::EditionCardComponent` section for the
mechanics. A right-click on the cover is the fast path for the single
most common correction: a panel rolls out in place from the cover
(not a centered `<dialog>`) listing just the covers on file, one click
to swap.

This is deliberately not a `PendingDecision` — nothing is "resolved,"
there's no queue, and it's available for any edition at any time,
independent of whether ISFDB enrichment ever flagged it. The three
existing review kinds (`enrichment_conflict`, `enrichment_printing_choice`,
`edition_reconciliation`) stay as they are — this is a fourth, general
escape hatch alongside them, not a replacement.

Since 2026-09-04, `CoverApplier.plan(..., authoritative: true)` (used
only by `IsfdbEditionEnricher`, whose own `enrich` never reaches it
without an isbn-confident printing match already in hand) is the actual
"relaxed about trusting an ISBN-matched ISFDB cover" behavior this escape
hatch was built to backstop — a differing cover fills outright instead of
raising `enrichment_conflict`. `Enrichment::SourceRecorder.integrate` also
auto-resolves any stale `enrichment_conflict` decision left over from
before that fetch started committing cleanly, so the backlog this
produced (94% of it a cover-only dispute, confirmed against real
`PendingDecision` data — see `edition_metadata_reconcile` in the
project's own memory) is expected to clear on the next bulk enrichment
run rather than sit stale.

## Explicitly out of scope for this phase

- ~~Any UI. Verification happens via Rails console...~~ **Superseded**: a
  real UI now exists — the `PendingDecision` review queue (3-card
  comparison: current catalog state, other known providers for reference,
  the proposing source's fields with checkboxes), per `docs/UI_PRINCIPLES.md`.
  See the review-UI addendum below.
- Reverse sync (opsimath → Goodreads) — still out of scope, but not for
  the reason originally stated here. This was originally framed as
  "Goodreads is the source of truth for now, deliberately" — corrected
  (`PHILOSOPHY.md` principle 20): sync direction and data trust turned
  out to be separate questions, and Goodreads is *not* treated as a
  trusted source of truth for catalog data, even though sync still only
  flows one way. Sync stays one-way because that's what keeps your
  community/network presence current, independent of trust; inverting it
  is a real future direction, not this phase, for that reason alone.
- Any `isfdb-adapter` API changes — use it as-is; revisit only on real
  friction.
