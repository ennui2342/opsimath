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
  something changed. Of the remaining 521 substring-containing pairs, 442
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
  region-flavored pairs are no longer special-cased — all substring
  variants merge toward the more complete form — and what actually gates
  the merge is the new multi-field check below, not whether the extra
  text looks like a territory marker.
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
candidate field before committing any of them (via
`Enrichment::FieldApplier.plan`/`.commit`, split out for exactly this),
rather than deciding field-by-field as it goes. Plain fills are always
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
`kind: reread_conflict` (a `currently-reading` event fires while a
`Reading` for that work is already open — genuinely ambiguous: duplicate
event, a forgotten-to-close previous read, or an intentional reread
starting before the last one's paperwork caught up).

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
`possible_duplicate_work` `ShelfSync` raises, one `sync_summary` per run,
and `sync_error` if the run itself blows up (re-raised after notifying,
so Solid Queue's own retry/failure tracking isn't short-circuited).

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
  `FieldApplier#find_or_create_conflict`/`IsfdbEditionEnricher
  #create_edition_mismatch` for the two payload shapes this reads.

**A newly auto-created `Edition` also gets ISFDB enrichment triggered
immediately, scoped to just that one `Edition`** — a deliberate design
choice to satisfy "notify on the Goodreads updater's own activity"
without flooding Discord: this is a *separate, per-item* call, not a
hook into the existing bulk `IsfdbEnrichmentJob`/`isfdb:enrich_editions`
rake task, which stays completely untouched and silent (a full-library
run would otherwise generate hundreds of messages). Any conflict this
per-item enrichment raises gets its own `pending_decision` notification,
same as `ShelfSync`'s own.

## Explicitly out of scope for this phase

- Any UI. Verification happens via Rails console or, at most, a minimal
  read-only view — not a reason to design screens yet.
- Reverse sync (opsimath → Goodreads). Goodreads is the source of truth
  for now, deliberately, because it's what keeps your community/network
  presence in sync; inverting that is a real future direction, not this
  phase.
- Any `isfdb-adapter` API changes — use it as-is; revisit only on real
  friction.
