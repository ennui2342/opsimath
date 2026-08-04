# Philosophy & design principles

This document exists so that as the project grows, new decisions can be
checked against *why* the project exists, not just against whatever the
schema happens to look like at the time. Read this before proposing a
schema change that doesn't obviously fit `DATA_MODEL.md`.

## What this is

A personal system for one person (Mark) to catalog a physical book
collection — mostly SF paperbacks, often lacking an ISBN — track reading
(including rereads) independently of any single platform, and manage short
reviews published as **scifipraxis** across Instagram, Goodreads, and a
personal website.

It is not a shared/multi-tenant library system, not a lending-library
tracker, and not an ebook-file manager. Where those concerns would pull the
data model in a different direction, they lose.

## Lineage

This project is a spiritual fork of [librarium](https://github.com/FireBall1725/librarium)
(Go API + React web, self-hosted book tracker) — PRs upstream aren't being
accepted, so this is a from-scratch rebuild — in Ruby on Rails, per
principle 17, not the project's original Python starting point — that
keeps what worked and deliberately abandons what didn't fit a single
collector's use case.
Concretely carried over:

- The **Work/Edition split** (librarium's `books`/`book_editions`) — one
  abstract book, many physical/digital manifestations.
- **Contributors as a shared entity with free-text roles** rather than a
  fixed enum — cheap to extend to "cover artist," which matters a lot for
  SF paperback collecting and which librarium's own schema already allowed
  without realizing how far it could be pushed.
- **Series with optional named arcs** (`series_arcs`) — useful for both
  straightforwardly-numbered lines and mega-series with sub-arcs.
- The general shape of a **provider/enrichment pattern** for pulling
  metadata from external sources (ISFDB, OpenLibrary) rather than hardcoding
  one API. `~/projects/isfdb-adapter` — a self-hosted ISFDB mirror + JSON
  API, already built as librarium's ISFDB provider backend — is directly
  reusable here too, and its actual schema (not just ISFDB's help docs) has
  independently confirmed several of this document's calls: `pub_content`
  is exactly the ordered edition-contents list in principle 3;
  `canonical_author` (title-level) vs. `pub_authors` (pub-level, used as a
  fallback) is the same work-credit/edition-credit split as principle 8's
  `WorkContributor`/`EditionContributor`.

Deliberately dropped:

- Multi-tenancy, RBAC, `libraries`/`library_memberships`, sharing/permissions
  — none of it serves a single collector, and it's real schema weight
  (roughly a third of librarium's `init_schema.up.sql`).
- ISBN as an identity/dedup key (see below).
- A single mutable read-status per book (see below).
- **Librarium's `shelves`/`book_shelves`** (user-defined, ordered, colored
  virtual groupings — "currently reading," "favorites") — not carried
  forward as their own entity because their job splits cleanly across
  three things this project already has: `Reading.status` for actual
  reading state, `Tag` for arbitrary personal labels, and `WishlistItem`
  for want-to-read. A dedicated `Shelf` concept would just be a fourth,
  overlapping way to say the same things.

## Principles

### 1. Work → Edition → Copy, not FRBR's full four-tier model

Library science's FRBR model (Work → Expression → Manifestation → Item) adds
an "Expression" tier — a work's realization in a given language/version,
independent of physical form — mainly to avoid re-describing a translation
across many publishers' editions of it. That's a shared-catalog problem.
For one person's shelf it buys nothing, so it's collapsed:

- **Work** — the abstract book (title, original author(s), first
  publication year). One row per intellectual creation, matching librarium's
  `books` table but named for what it actually is (librarium's own naming —
  a "book" that's actually work-level — is the kind of ambiguity to avoid
  here).
- **Edition** — a specific printing/format (this paperback printing, that
  audiobook, this omnibus). Editions carry format, publisher, publish date,
  page count, and edition-specific contributors (translator, cover artist,
  narrator).
- **Copy** — a specific physical object you own. Confirmed as worth the
  extra tier over a bare count: a real collector's shelf has copies with
  their own condition, provenance, and inscriptions, and it's common to end
  up owning two different printings — or, less happily, an accidental
  duplicate — of the same edition. See `DATA_MODEL.md`.

### 2. ISBN is a fact about an edition, never its identity

Librarium's own dedup migration (`000007_dedupe_books_by_isbn`) uses ISBN as
the sole key for merging duplicate books and editions, and explicitly
declines to dedupe anything without one — "title/author matching is too
lossy to do automatically." For a pre-1970s/small-press-heavy SF paperback
collection, that's the common case, not the exception.

So: **identifiers are a flexible, optional bag**, not schema-load-bearing
columns. ISBN-13, ISBN-10, the pre-ISBN SBN, OCLC number, LCCN, ASIN,
OpenLibrary/ISFDB IDs, and — importantly for vintage SF — **publisher
catalog numbers** (Ace's `D-103`/`F-173`/`G-574`, DAW's `UQ1010`) are all
just entries in the same identifiers table. None of them is required, and
none of them is trusted as a unique key for automatic merging; matching
ambiguous/no-identifier editions stays a manual, reviewed action, not an
automatic migration.

### 3. An Edition's contents are an ordered list of Works, not a single link

Ace Doubles — two unrelated novels bound dos-à-dos as a single physical
object with two covers — are common enough in this collection to design for
up front rather than special-case later. The first draft of this principle
stopped at "Edition↔Work is many-to-many," which was really just an
Ace-Doubles special case in disguise.

ISFDB's own model (checked directly against its FAQ/help docs) generalizes
further, and it's worth copying the generalization rather than the special
case: a Publication's contents are simply an ordered list of Titles, full
stop. The exact same mechanism accounts for an Ace Double (two novel-length
contents), a single-author collection or anthology (many story-length
contents), and an omnibus (several full novels bound as one). There's no
reason to model "two novels in one book" differently from "twelve stories
in one book" — it's the same fact at a different scale. So `EditionContent`
carries a `display_order` (and, where it matters, a `billing` like
"front"/"back" for a dos-à-dos or a starting page number for anthology
contents) rather than being a bare many-to-many link. An anthology's own
`Work` row is itself one of its edition's contents, not something outside
the list — see `DATA_MODEL.md`'s `EditionContent` for why.

### 4. Reading is an append-only log, not a status field

Librarium (and Goodreads' own CSV export, for what it's worth — `Read
Count` is a bare int, `Date Read` a single date) models "have I read this"
as one mutable start/finish/rating/review per (user, book). A second read
overwrites the first read's dates, rating, and review outright — there's no
way to say "loved it in 2019, lukewarm on the reread in 2025." This is a
real, previously-unsolved gap (confirmed independently — another book
tracker has an open issue for exactly this), not invented complexity.

So: every read-through is its own row, forever. "Have I read this" is a
derived query (does at least one reading exist), not a stored field.

### 5. A published review is not the same thing as a private reading note

Reviews published as scifipraxis are curated, dated, cross-posted content
— a different thing from private notes jotted while reading. They're
modeled as their own entity, linked to (but independent of) a specific
reading. **Scope for now**: text, rating, and a publish date live as real
columns; *which channels it went out to and when* (Instagram post, Goodreads
review, website) is deliberately left as a flexible field rather than a
fully normalized per-channel table until real usage shows the actual
pattern — three platforms with different post/edit/repost semantics is
likely to teach us something a first schema would guess wrong.

### 6. Physical-collection-first

Condition, acquisition (where/when/price), and shelf/box location are
first-class fields on `Copy`, not an afterthought bolted onto an
ebook-file-management system the way librarium's `storage_locations` /
`edition_files` (built around organizing files on disk) implies.

### 7. A Work can have more than one title, lightly

Vintage SF gets retitled constantly — a different UK/US title, a magazine
serialization title, a working title later dropped. Both ISFDB (variant
titles, canonicalized under a parent Title) and MARC (the 240 "uniform
title" field, for exactly the same reason: collating a work under
whichever titles it's actually been published as) independently arrived at
"a work needs to be findable by more than one title." That's real
convergence from two unrelated bibliographic traditions, not a quirk of
either.

What's *not* copied is the machinery either of them builds around it.
ISFDB gives every variant its own full Title record (own language, own
notes, pointing back to a canonical parent — "variants of variants are not
allowed"); MARC's uniform title is a full authority-controlled heading.
Both exist to keep many independent editors' cataloging consistent across
a shared database. That problem doesn't exist here, so the version that's
worth building is much smaller: a flat list of alternate titles on `Work`
(title text + a free note like "UK title" / "magazine title"), searchable
but not itself a first-class entity with its own metadata.

### 8. A byline is a fact about a credit, not about a person

ISFDB gives every pseudonym — including joint pseudonyms, where several
real authors share one house name (e.g. "Robert Randall" was Silverberg and
Garrett writing together) — its own author record, linked back to whoever's
really behind it. That's more machinery than a personal collection needs:
nobody's browsing this collection *by* pseudonym as a first-class path the
way ISFDB's users browse a shared database that way.

The fact worth keeping is narrower: sometimes the name printed on the book
isn't the name the work is filed under. So `WorkContributor` and
`EditionContributor` both carry an optional `credited_as` — the byline as
actually printed, alongside the real link to the canonical `Contributor`.
A joint pseudonym just means two contributor rows with the same role and
the same `credited_as` value; no separate pseudonym-identity graph needed.

### 9. Prefer an existing standard over inventing a vocabulary

Standing rule for this project, not just a one-off call: when defining any
taxonomy, vocabulary, or ontology, check whether an existing standard
already covers it, and default to adopting that rather than rolling our
own — decades of library-science and publishing-industry work have already
fought most of these battles. Depart from a standard only where it
contradicts an actual use case here, and say why. Three applications so far:

- **Contributor roles** (principle 8's `role` field) — ONIX Contributor
  Role Codelist (List 17) / MARC relator terms, not an invented list.
- **Edition format detail.** ISFDB's own `pub_ptype` column (checked
  directly in `isfdb-adapter`) distinguishes `hc`/`tp`/`pb`/`ebook`/`audio
  CD` — proof this project's plain `paperback`/`hardcover`/`ebook`/
  `audiobook` was too coarse, since it can't tell a mass-market paperback
  from a trade paperback. Rather than adopt ISFDB's own shorthand, though,
  go one level further to the actual industry standard behind that same
  distinction: ONIX Product Form (Codelist 150) for the top-level format,
  and Product Form Detail (Codelist 175) for the paperback subtype —
  `B101` mass-market/rack, `B102`/`B106` trade (US/UK), `B104`/`B105` UK
  A-format/B-format. That last pair matters concretely here: UK vintage SF
  paperbacks (Panther, Corgi, NEL) are routinely described by collectors in
  exactly those terms. See `DATA_MODEL.md`'s `Edition.format_detail`.
- **Genre.** Thema (EDItEUR's international subject-classification
  scheme — the same body that maintains ONIX, so this stays inside one
  standards family alongside contributor roles and format) has a
  ready-made `FL` Science Fiction subtree: `FLC` classic, `FLH` hard SF,
  `FLS` space opera, `FLQ` apocalyptic/post-apocalyptic, `FLG` time
  travel, `FLR` military, `FLM` steampunk, `FLU` aliens/UFOs, `FLW` space
  exploration, `FLP` near future, `FLJ` cosy — adopted as the seed
  vocabulary for `Genre` rather than inventing subgenre labels from
  scratch. BISAC's older, US-centric `FIC028` family covers similar ground
  and is worth cross-referencing since it's what's often actually printed
  on a US paperback's back cover, but Thema is the primary vocabulary here
  given the ONIX consistency. ISFDB itself was checked and has no genre/
  subject taxonomy at all (confirmed against `isfdb-adapter`'s mirrored
  table list) — it's a bibliographic database, not a subject-classification
  one, so it wasn't a candidate here despite being the go-to source
  elsewhere in this document.

As elsewhere, "adopt" means *seed and cross-reference*, not *enforce as a
closed enum* — per-field free text stays legal for anything a standard
doesn't cover, matching this project's general preference for flexibility
over rigid structure in a single-user tool.

### 10. Keep what enrichment fetched, not just what it wrote

Librarium (like Calibre) writes enrichment straight into `books`/
`book_editions` fields with no separate record of where a value came from
— closer to "overwrite and forget" than anything else surveyed here.
Four other systems were checked for how they handle multiple external
sources feeding one record, and none of their full answers fit a
single-user tool, but each contributes a piece:

- **Wikidata** models every value as a statement with its own
  qualifiers, references, and rank (preferred/normal/deprecated) when
  sources disagree — nothing is ever silently overwritten. Built to
  resolve disputes among thousands of independent editors; that problem
  doesn't exist here.
- **MARC 883 ("Metadata Provenance")**, added in 2012 specifically for
  automated/linked-data enrichment, links a field to the URI of the
  process that generated it and when — real precedent, in a formal
  cataloging standard, that "which automated process populated this
  field" is worth recording at all.
- **Open Library** keeps it much lighter: `source_records` is just a flat
  list of source identifiers that contributed to a merged Edition —
  record-level attribution, no per-field history, no superseded values
  kept.
- **MusicBrainz** goes the other way — every edit is proposed, voted on,
  and permanently logged. Real audit history, but in service of
  community dispute-resolution, the same problem Wikidata solves.
- **MDM (master data management)** practice calls the general "which
  source wins" problem *survivorship*: rank sources, prefer recency, and
  — the useful bit — route anything that can't be resolved automatically
  to an exception bucket for manual review rather than guessing.

The shape that fits here: keep the actual fetched record (not just Open
Library's bare identifier — affordable at this scale, and it means a
source can be re-diffed later or fields re-derived if the mapping logic
improves), tag which provider currently backs each single-valued field
(not Wikidata's full statement history — there's no dispute to arbitrate,
just "why does this field have this value"), and treat any provider
update to an already-populated field as something to confirm, not apply —
per MDM's exception-bucket idea, and because a personal collection is
small enough that reviewing every non-empty-field change costs nothing.
Only empty fields auto-fill without a prompt. See `DATA_MODEL.md`'s
`EnrichmentRecord` and `field_sources`.

Plural fields need none of this apparatus — `EditionIdentifier` and
`WorkAlternateTitle` already let ISFDB's OCLC number and OpenLibrary's
OCLC number coexist without conflict, since they're one-to-many by
design. The provenance question only exists for single-valued fields
(title, page count, cover, publish date) where two sources can actually
disagree.

### 11. Other physical collecting hobbies have already hit these same problems

The "no ISBN, many editions" problem isn't specific to old SF paperbacks —
checking a few adjacent collecting domains turned up direct precedent for
parts of this model, and one genuinely new addition each from two of them:

- **Vinyl records (Discogs)** — a fourth independent case (after librarium,
  ISFDB, and Discogs itself) of splitting an abstract release (Master)
  from its specific pressings (Release), and Discogs' own guidelines
  document releases with no barcode at all, same shape as a paperback with
  no ISBN. New addition: Discogs' **matrix/runout number** — a code
  physically etched into the vinyl during manufacturing, sometimes the
  *only* way to distinguish two pressings that agree on catalog number,
  label, and year. Vintage mass-market paperbacks have a direct
  equivalent already used by collectors — the **printer's key**, a small
  code (often copyright-page or back-cover) identifying the actual print
  run, sometimes more reliable than a stated "1st printing" claim. Added
  as a recommended `id_type` on `EditionIdentifier`, not a new field —
  it's the same shape as `publisher_catalog_number`.
- **Comics (Grand Comics Database)** — variant-cover issues are their own
  catalog record but point back to a base issue, sharing its contents/
  credits; GCD also distinguishes a trivial printing-variant (same cover,
  different tint, later printing) from a genuine second edition (revised
  content, new cover, issued much later) — validating that this project's
  existing `printing` (free text) vs. `edition_name` split is already the
  right granularity, nothing to add there. What *is* new: an optional
  self-referencing `Edition.variant_of_edition_id`, so a later
  variant-cover printing of the same text can be grouped with its base
  edition without conflating their distinct `cover_image`/cover-artist
  credit.
- **Philately** — the strongest validation yet of principle 2's identifier
  bag, not a new addition. Scott, Stanley Gibbons, and Michel each assign
  the *same physical stamp* their own independent catalog number, none
  canonical; serious collectors hold all of them and cross-reference
  constantly rather than picking one "true" scheme. Exactly the posture
  `EditionIdentifier` already takes.
- **Wine (CellarTracker)** — the closest analogy to the *combined* shape
  (collection + consumption log + review), not just the identifier
  problem. Bottles are tracked individually and marked drunk/relocated/
  given-away (`Copy`/`Copy.disposition`), and — the load-bearing point —
  "tasting notes are not tied to consumed bottles": a note can be logged
  any time, independent of whether you drank your own tracked bottle.
  Independent validation of principle 4/5's `Reading`/`Review` split from
  an unrelated collecting domain. One instructive difference: a
  CellarTracker drink-event always ties to one specific bottle (you can't
  drink wine without consuming a physical one), while `Reading.copy_id` is
  deliberately optional — reading doesn't always consume or require a
  specific owned copy the way drinking does (a library ebook of a
  paperback you separately own in print). Confirms `Reading` is already
  general enough where wine's model doesn't need to be.

### 12. Awards are real, structured, currently-displayed data

`~/projects/obsidian-wikidata-lookup` (an Obsidian plugin fetching
bibliographic data from Wikidata for scifipraxis reviews) and
`~/projects/scifipraxis` (the Jekyll site those reviews publish to) are
worth treating as ground truth, not just another adjacent system —
they're the *actual* enrichment/publishing pipeline principles 5 and 10
were designed around, already running in production, not a hypothetical.
Checking them directly surfaced two concrete things:

- **Principle 10's design is already built and working**, independently
  of this document. The plugin writes a Wikidata QID pointer into a
  review's front matter and keeps the *full* fetched record as its own
  separate file (`_data/wikidata/<qid>.yml`), pulling only one derived
  field (a generated meta-description) back into the primary note. That
  is `EnrichmentRecord` plus `field_sources`, field-for-field — the
  strongest validation this principle has, since it's not analogous, it's
  the same problem being solved by the same person already.
- **Awards were entirely missing from this data model.** The plugin
  fetches `awards_won`/`awards_nominated` (Wikidata `P166`/`P1411`,
  qualified by `P585` for year) and the site renders them as prominent
  badges and includes them in its `schema.org` JSON-LD `award` field — a
  real, currently-displayed feature. Added `Award`/`WorkAward` to
  `DATA_MODEL.md`, Work-level (matching Wikidata's own placement, not
  Edition-level), seeded/cross-referenced against Wikidata's own award
  items rather than free-text award names, per principle 9.
- One deliberately-not-modeled counterpoint from the same source: the
  plugin also fetches `settings` (Wikidata's `P840` "narrative location")
  but the live site never renders it — dead data in production today.
  Not added here either; building a controlled vocabulary for fictional
  settings would be solving a problem the real system doesn't actually
  have yet. Plain `Tag` already covers it if that ever changes.
- **Rating scale, settled by the same review**: neither `Reading.rating`
  nor `Review.rating` had a specified scale before this. The live site's
  actual scale — 0–5, half-star increments (`page.stars`, schema.org
  `bestRating: 5`) — is now both, per confirmation, rather than either
  being invented independently and needing a conversion step later.

### 13. Scheduling and job execution are bought, not built — self-contained, not externally triggered

First draft of this principle recommended triggering batch enrichment via
an external cron/k8s CronJob, matching how `goodreads-librarium-sync`
works today. Reconsidered: that makes opsimath depend on infrastructure
outside its own control that may not exist or may change, for a
self-hosted personal tool that should stand on its own. The fix isn't to
build an in-app scheduler by hand, though (that's librarium's own
`job_schedules` table, and hand-rolling scheduling/retry/persistence logic
is exactly the kind of solved infrastructure problem worth not
reinventing — see principle 16). Instead: a maintained library that
persists its own schedule/queue in the same database the app already
uses, so the app owns its scheduling loop with no external dependency at
all.

Now that principle 17 has settled on Ruby: **Solid Queue** — Rails 8's
own default Active Job backend, database-backed (no Redis), supporting
delayed/recurring jobs, concurrency controls, and priorities out of the
box. This is a stronger fit than anything found during the earlier
Python-specific search (APScheduler, Procrastinate, Huey — all legitimate
in their own ecosystem, but Solid Queue is a first-party framework
default here, not a third-party pick-and-assemble choice), and it directly
answers this principle's self-containment requirement natively.

Solid Queue's row-locking approach (`FOR UPDATE SKIP LOCKED`) wants
Postgres or MySQL to perform well under concurrent workers — a real,
if minor, factor in the still-open storage-engine decision, though a
single-user app's actual concurrency needs are modest enough that this
shouldn't be the deciding factor on its own. Worth weighing when that
decision actually gets made, not before.

**Correction, made explicit after actually building this and hitting real
friction setting it up** (a Rails multi-database configuration quirk,
`db:prepare` not cascading to a same-named secondary database role — see
`docker-compose.yml`'s comments): the "self-contained, no external
dependency" framing above overstated the case against Redis specifically.
That framing is really about not depending on infrastructure *outside
opsimath's own control* (an external cron job on a different system) — a
Redis container living in opsimath's *own* `docker-compose.yml`/k8s
manifests wouldn't actually be "external" in that sense, any more than
Postgres already isn't. Asked directly whether the setup friction meant
this was fighting the grain; the answer, confirmed together, was no — the
friction was mostly self-inflicted (an earlier `--skip-bundle` shortcut
broke Solid Queue's own install hooks) plus one now-fixed, one-time
config quirk, not an ongoing tax. The reasons that actually hold up
independent of the "external infra" framing: transactional consistency
(a job enqueues in the same DB transaction as the business logic that
creates it, which a Redis-backed queue can't offer as cleanly), it's
Rails 8's own first-party default rather than a third-party addition
(principle 16), and it's one fewer service to operate for the life of
this app, not just at setup.

What stays custom, because no library can know it: which of the (say)
200 books in one enrichment run succeeded or failed, and why. A thin
domain-specific `JobItem`-equivalent (`entity_type`/`entity_id`, `status`,
`message`, correlated to whichever library's own run/task identifier
rather than a bespoke envelope table) covers that — see `DATA_MODEL.md`.
Librarium's own `Job`/`JobEvent` umbrella (the outer "was this run
scheduled, when did it start/finish, overall status" bookkeeping) is
dropped entirely in favor of whichever library's own run-tracking; keeping
it too would just be re-litigating principle 16 in the other direction.

### 14. A batch run needs somewhere to put a decision it can't make itself

Principle 10 says any provider update to an already-populated field
"always surfaces a confirm/diff step" — true for a one-off lookup, but it
doesn't survive contact with principle 13's batch runs: a nightly
enrichment refresh over the whole collection can't block on two hundred
synchronous confirmations. The fix is a queue, not a rule change: a
`PendingDecision` (kind-tagged — `enrichment_field_conflict` today,
extendable later to a possible-duplicate-books suggestion or a
series-match candidate without inventing a new mechanism each time —
JSON payload, `pending`/`accepted`/`rejected`, optional `run_id`
correlating back to whichever run produced it). A run that hits something
needing judgment creates a `PendingDecision` instead of blocking; review
happens whenever, not mid-batch. This is the same "survivorship exception
bucket" idea from principle 10's MDM citation, just given an actual place
to live now that batch processing exists.

Checked directly against the heavier end of the workflow-engine space
(Airflow, Prefect, Temporal) before deciding to keep this custom, per
principle 16: those are DAG orchestration engines for distributed
pipelines, each bringing its own database/scheduler/often a webserver —
wildly the wrong shape and a large infrastructure burden for what's
genuinely a three-state review queue. Custom is correct here specifically
because nothing off-the-shelf fits at this scale, not by default.

### 15. Audit/versioning is bought too — a library, not a hand-rolled history table

Librarium's `sync_*` migrations (per-field last-write-wins timestamps,
tombstones, append-only history for its two most-contested free-text
fields, a `sync_clients` table tracking per-device cursors for tombstone
GC) aren't a general audit log — read directly, they're solving multi-
device offline-sync conflict resolution specifically: two independent
clients edited the same data while disconnected and need to reconcile
without silently dropping either version. Opsimath has no offline-capable
client today, so none of that machinery is being built now. But an
offline client (a phone app usable without connectivity) is a real
possible future, not ruled out — so this is deferred, not foreclosed:
when/if it becomes real, librarium's `000018`–`000021` migrations are the
concrete reference design to revisit, not something to redesign from
scratch.

In the meantime, what actually matters for a single always-connected user
— for different reasons than sync — is covered by one maintained library
rather than the two hand-rolled mechanisms this document originally
proposed (a generalized `FreeTextHistory` table and a `deleted_at`
convention). Per principle 16, and now that principle 17 has settled on
Ruby: **PaperTrail** — versions ActiveRecord models automatically, with a
continuous, single-lineage maintenance history back to 2010 (still
actively updated) rather than the forked-package situation found for the
Python equivalent (SQLAlchemy-Continuum/SQLAlchemy-History). Revert to
any past state, including recovering a row that was deleted. Strictly
more capable than what was designed here by hand (full history at any
past point, not just "current value plus one prior value"), for less
custom code, applied selectively to the entities/fields that actually
need it:

- `Review.text` and `Reading.private_notes` — the free-text fields
  expensive to lose to a fat-fingered overwrite. Not sync-conflict
  resolution — "don't silently destroy a carefully-written draft,"
  valuable even with exactly one device.
- `Work`, `Edition`, `Copy`, `Contributor`, `Series` — the entities
  expensive to re-catalog by hand if accidentally deleted. Cataloging a
  pre-ISBN paperback by hand is real effort; recovering from an accidental
  delete shouldn't cost redoing it.

`EnrichmentRecord` still doesn't need this — it's already append-only (a
new row per fetch, never overwritten), which is most of "what did the
data used to say" for anything automatically sourced, for free, per
principle 10.

Everything beyond what the versioning library covers relies on regular
whole-database backups (e.g. `litestream` for SQLite, `pg_dump` for
Postgres) as the actual disaster-recovery mechanism, deliberately, rather
than more bespoke machinery on top.

### 16. Build what's core and differentiating; buy (open source) everything else

Standing rule, stated explicitly rather than left implicit. The test
isn't "is this generic" — it's sharper than that: **is this thing core to
opsimath, part of what actually differentiates it and delivers its core
use cases — or are we just telling ourselves it's special because we're
the ones building it?** ("Are we really a special snowflake, or do we
just want to think we're special" — worth asking directly, every time,
because the second answer is the more common one.) When the honest answer
is "not core," the right move is a maintained open-source library, not
custom code — commercial/SaaS options aren't in scope here at all, this
project self-hosts, so "buy" always means "adopt an OSS dependency," never
"pay for a service."

This is the same underlying value as principle 9 ("prefer an existing
standard over inventing a vocabulary") one layer down — applied to code
and mechanisms instead of data formats and taxonomies. A contributor-role
vocabulary or a genre taxonomy is exactly as non-differentiating as a job
scheduler: none of them are why opsimath exists, so none of them are worth
inventing from scratch.

Re-examined honestly against this sharper test, not just restated:

- **Buy — clearly non-core**: scheduling/execution (principle 13 —
  Solid Queue instead of a hand-rolled `job_schedules`) and audit/
  versioning (principle 15 — PaperTrail instead of a hand-rolled
  `FreeTextHistory`/`deleted_at`). Neither is remotely what opsimath is
  *for* — a personal
  SF collection tracker isn't differentiated by how it schedules a
  background refresh or versions a row, and both problems already have
  mature libraries with far more field experience finding their edge
  cases than this project ever will.
- **Build — `PendingDecision` (principle 14), on a closer look at *why***:
  the honest answer to the snowflake test here is more nuanced than the
  other two. The generic shape (a kind-tagged queue with a payload and a
  pending/accepted/rejected status) isn't itself differentiating — lots
  of systems have a review queue. What *is* core is the underlying stance
  behind it: never let automated enrichment silently overwrite trusted,
  hand-verified bibliographic data (principle 10) — that's a direct,
  central response to the exact failure this project was started to avoid
  (librarium and Calibre both just overwrite). So it's less "build because
  nothing off-the-shelf fits" (though that's also true — Airflow/Prefect/
  Temporal are DAG-orchestration engines, wildly the wrong shape for a
  three-state review queue) and more "build because the specific judgment
  calls being queued *are* opsimath's differentiation, even though the
  queue mechanism holding them looks generic from a distance."
- **Build — the actual bibliographic model** (`Work`/`Edition`/`Copy`,
  `EditionIdentifier`, `Reading`/`Review`, `Award`, and everything else in
  this document outside "Operational entities"): unambiguously core.
  This *is* opsimath's differentiation from librarium/Calibre/Goodreads —
  not a close call, and the whole reason five of this document's other
  principles exist.

The test either way: is this a generic problem (many other systems need
exactly this, with hard-won edge cases already handled), or is it
something that only makes sense in terms of this project's own domain
(Work, Edition, Copy, a byline, a scifipraxis review)? Genuinely bounded,
domain-specific glue — like `JobItem`'s "which book succeeded or failed"
or `PendingDecision`'s payload shape — stays custom regardless, because no
library could know what it means without this project's own domain
knowledge built in.

### 17. Ruby (Rails), not Python — chosen over the project's own starting premise

This project started (see `README.md`'s original framing) with Python
simply stated as the language, for two reasons that turned out not to
hold up once actually examined: a wish to learn Python on this project
specifically, and a belief that Python's larger share of LLM training
data would mean more reliable AI-generated code. Both were reconsidered
directly rather than left as an unexamined starting assumption.

- **The training-data belief has a real basis but doesn't actually apply
  here.** There is a documented correlation between a language's training
  volume and code-generation quality — but the effect is strongest for
  genuinely low-resource languages, not for a two-decades-mature,
  heavily-documented, convention-driven framework. Ruby on Rails is
  comfortably in the "very well represented" tier, not the sparse one
  where this effect actually bites. Rails' own strong opinions ("the
  Rails Way") plausibly offset a chunk of the smaller raw corpus by
  making generated code more consistent per line, though this is a
  reasonable inference, not a measured claim.
- **The learning goal is real but separable.** Wanting to learn Python is
  worth pursuing — just not by coupling it to the one project meant to
  hold years of hand-typed cataloging effort and actually be trusted
  long-term. A lower-stakes project is the better vehicle for that.
- **What actually should have driven the decision, and now does: Mark's
  own ability to read, critique, and debug the code independently.** An
  AI-generated codebase its owner can't critically evaluate is a real
  long-term risk — bugs and data-loss edge cases go unnoticed longer.
  Ruby is Mark's own fluent language; Python would not have been.
- **Concrete ecosystem wins, not just the language itself**: Rails 8
  ships **Solid Queue** (principle 13) and the mature **PaperTrail** gem
  (principle 15) as first-party-adjacent, batteries-included answers to
  two needs this document already spent real effort on in the
  Python-specific framing — a direct instance of principle 16's "buy"
  side working out better in Rails than it did in the language originally
  assumed.
- **Turbo Native (principle 18) directly answers a specific, previously
  unresolved past problem**: an earlier project hit real pain running
  HTMX inside a PWA — full-navigation-style reloads fighting against a
  PWA's "feel like an app" expectations, lost scroll position, workarounds
  needed. Turbo Native wraps a Hotwire web app in a genuine native
  iOS/Android shell rather than approximating native behavior through a
  PWA/service-worker layer — a materially better fit for a need
  (principle 15's deferred mobile client) this project already has, not
  just a nicer version of the same idea that failed before.

`~/projects/isfdb-adapter` (Python/FastAPI) is unaffected — it's a
separate, already-deployed service opsimath talks to over HTTP, with no
need to share a language with whatever calls it.

### 18. Server-rendered by default; command-oriented writes; a narrow, earned JSON API

Prompted directly by librarium's own stated pain: good frontend/backend
separation, but a complicated API surface needing constant updates for
anything new on the frontend. Checked against current practice rather
than assumed:

- **GraphQL and a librarium-style bespoke-endpoint-per-frontend-need API
  were both considered and rejected for now** — the 2026 consensus on
  GraphQL is blunt: "the worst outcome is GraphQL adopted for one web
  app — all of the cost, none of the payoff," and it only earns its
  infrastructure tax with multiple heterogeneous clients against a
  genuinely complex data graph, which opsimath doesn't have. A BFF-style
  bespoke API per frontend view has the same problem in the other
  direction — librarium's actual complaint, not a hypothetical one.
- **The primary web UI is server-rendered — Hotwire (Turbo + Stimulus),
  not a separate SPA plus a JSON API contract to keep in sync.** This
  dissolves librarium's stated problem for the primary UI rather than
  managing it better: there's no separate frontend/backend contract to
  update in the first place, since the HTML template *is* the contract,
  versioned in the same commit as the controller action that renders it.
  Turbo Drive avoids full page reloads by default; Stimulus covers the
  small amount of client-side behavior a template needs without reaching
  for a full JS framework; Turbo Native (principle 17) is the answer
  already lined up for an eventual mobile client, precisely where raw
  HTMX caused real pain before. **Tailwind** for styling — a pure
  presentation-layer concern that doesn't compete with or complicate
  Turbo/Stimulus's behavior layer, and the pairing Mark's used
  successfully on past Rails projects.
- **The CLI calls the same Ruby service-layer code directly, not over
  HTTP** — it runs on the same machine, so it doesn't need a network API
  at all. Shrinks what "the API" has to cover before even getting to the
  next point.
- **A real JSON API stays narrow and earned**, scoped to what genuinely
  needs one: a future remote/offline client (principle 15, deferred not
  foreclosed) or programmatic integration (an eventual Goodreads-sync
  endpoint, same shape as the existing aswarm/librarium pattern). Within
  it, the split follows principle 10/14's own logic rather than uniform
  CRUD: plain CRUD-ish actions for genuine data management with no real
  rule to protect (edit a `Contributor`'s bio, add a `StorageLocation`),
  and explicit command/task-oriented actions wherever this document's own
  principles already decided a rule matters (`POST` a new `Reading` rather
  than `PATCH`ing a status field; `POST /pending_decisions/:id/accept`
  rather than a raw status edit) — so the API can't be used to quietly
  bypass the rules principles 4, 10, and 14 exist to enforce.
- Bonus alignment, not the reason on its own: command/task-shaped writes
  translate more naturally into an eventual offline-sync operation log
  (principle 15) than raw CRUD would, so this choice stays quietly
  compatible with that deferred future without building any of it now.

### 19. Concrete stack pins, and authentication is a login gate, not multi-tenancy

Rounding out the stack decisions, verified current rather than assumed:
**Ruby 4.0**, **Rails 8.1**, **Postgres** (settling principle 13's Solid
Queue coupling favorably in the process — see `DATA_MODEL.md`'s "Open
questions"), **Minitest + fixtures + Capybara system tests** (Rails'
own defaults, not RSpec/FactoryBot), and **Docker for local development**
(a `docker-compose` of web/Postgres/a Solid Queue worker service,
mirroring `~/projects/isfdb-adapter`'s own compose file structurally) to
keep the host OS clean. Eventual deployment is the k8s homelab cluster,
same as librarium and `isfdb-adapter` — deliberately not decided further
than that yet.

The asset pipeline follows the same self-containment value as principle
13: **importmap-rails** and **tailwindcss-rails** (Tailwind v4) are both
genuinely Node-free now (Tailwind v4 ships its own standalone CLI) —
no Webpack/esbuild/npm toolchain anywhere in the stack, not just no
external job-scheduling dependency.

**Authentication**: Rails 8's built-in `bin/rails generate authentication`
— a minimal `User`/`Session` scaffold (email/password, session tracking
with IP/user-agent, password reset), generated directly into the app
rather than pulled in as a gem. Chosen over Devise specifically because
Devise's extra modules (email confirmation, account locking, OAuth) are
solving problems opsimath doesn't have — the same principle 16 test
applied again. Worth being precise about what this does *not* reopen:
this is a login gate for the one owner, not a reversal of "no
multi-tenancy" (Non-goals, below) — no roles, no sharing, no per-library
membership hang off `User`/`Session`, and exactly one `User` row is ever
expected to exist. Alongside it, confirmed needed rather than deferred:
an `ApiToken` model for automation/integration access (matching
librarium's own PAT pattern), separate from the human login — real
near-term need, not speculative. See `DATA_MODEL.md`'s `User`/`Session`/
`ApiToken` entry.

### 20. Goodreads import/sync is the first feature built, and it's self-contained

Deliberately built before any UI — see `docs/INTEGRATIONS.md` for the full
design. Two reasons this comes first rather than last: it forces the
schema to meet real, messy data immediately (librarium's own experience
with Goodreads date handling is a fair warning), and it gives the rest of
the app real data to be built against rather than synthetic fixtures.
Checked directly against `~/projects/opsimath/import/`'s real 2,306-book
export before designing anything, rather than assuming its shape.

Two architecture decisions, both extending principles already established
rather than new ones:

- **Self-contained, not an external pipeline** — a Solid Queue recurring
  job inside opsimath, not the aswarm/Rhai pipeline pattern already
  proven for librarium (`goodreads-librarium-sync`/`-reading-sync`/
  `-read-sync`). The existing pipelines' *logic* (RSS mechanics,
  snapshot-based change detection, series-suffix stripping, matching) is
  ported directly — real, hard-won lessons, not rediscovered — but the
  *infrastructure* isn't, for the same reason principle 13 argued against
  external cron for enrichment: opsimath shouldn't depend on
  infrastructure outside its own control for something core to how it
  stays useful day to day.
- **Goodreads is the source of truth for now, deliberately, not
  permanently.** Goodreads' community/network value means it needs to
  stay in sync; the easiest way to guarantee that right now is one-way
  sync in. Inverting this (opsimath as source of truth, syncing back to
  Goodreads) is a real future direction, explicitly not this phase — see
  `docs/INTEGRATIONS.md`'s "out of scope."

### 21. Development practices, pinned down before writing the first line

- **Test-first, targeted rather than blanket TDD ceremony.** Earns its
  keep specifically on the data-integrity/business-logic layer — CSV
  import parsing, shelf matching/dedup, `Reading` creation rules,
  `PendingDecision` triggers — where a silent bug does real damage
  (a miscounted reread, a duplicated `Work`) and where `docs/
  INTEGRATIONS.md` already enumerates most of the tricky cases in
  advance (the `read_dates`-vs-`Read Count` distinction, series-in-title
  parsing, two date formats, ambiguous shelf matches) — close to a
  ready-made list of "write the failing test for this case, then make it
  pass." Not insisted on for plain scaffolding/CRUD views, where there's
  no subtle behavior to pin down. Fixtures for the risk-bearing tests are
  **real rows extracted from the actual export**, not synthetic data —
  already known to be representative, with any review/notes text in them
  replaced by placeholder text before committing (the full private
  export stays gitignored regardless, per the earlier discussion).
- **RuboCop and Brakeman from day one** — the same buy-don't-build
  instinct as principle 16, applied to style/security tooling: a
  maintained community ruleset beats inventing conventions ad hoc, and
  static security analysis matters given this becomes network-reachable
  once deployed (principle 19's login gate exists for the same reason).
- **Trunk-based, direct commits** — no feature-branch/PR ceremony for a
  solo project with no second reviewer; small, focused commits straight
  onto the main branch.
- **Commit after each coherent, tested slice, without waiting to be
  asked each time** — a deliberate change from the documentation phase's
  "only commit when explicitly requested." Still every commit is visible
  and reviewable after the fact; this just removes the per-commit
  approval step now that there's code, not just docs, being produced.

## Considered and explicitly not adopted

- **Calibre's `custom_columns`** (a schema for user-defined typed columns,
  avoiding migrations for new metadata fields) is a legitimately good
  pattern — Calibre's own scale proves it holds up. Not adopted: for a
  single-developer project, writing a real migration when a new field is
  needed is cheaper than building and maintaining a generic
  column-definition system to avoid writing migrations. Revisit only if
  schema-change friction becomes an actual recurring problem.
- **Z39.50/SRU** (library catalog retrieval protocols) don't inform the data
  model at all — they're transport/query protocols, not schemas, so there's
  nothing here to adopt or reject at that level. As a *future metadata
  provider* (alongside ISFDB/OpenLibrary) they'd mainly supply LCCN/OCLC
  numbers, which the identifier bag already accommodates — but most
  mass-market SF paperbacks were never catalogued by libraries at that
  granularity, so this is low-value and not worth building toward.

## Non-goals (for now)

- Multi-user support of any kind — sharing, roles, per-library membership.
  Revisit only if the actual need shows up — adding it later is a real
  migration, not a flag flip, and that's an accepted tradeoff for a
  simpler schema today. (This is a different axis from *authentication*:
  principle 19's login gate exists to keep the app from being open to
  anyone who can reach it on the network, not to support more than one
  person using it — a `User`/`Session` table is not multi-user support.)
- Ebook/audiobook file management (no `edition_files`-equivalent). This
  tracks a physical collection; digital editions are metadata rows, not
  files to be organized on disk.
- Lending/loan tracking — not a stated use case; add only if it becomes one.
