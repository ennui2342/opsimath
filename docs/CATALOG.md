# Catalogue management: opsimath as the source of truth

Goodreads removed RSS (October 2026), which ended the hourly sync that
fed opsimath. The alternatives were assessed and none fits (Mark,
2026-11-02): LibraryThing has a good catalogue but a thin API, a poor
interface, and no meaningful edition handling — it expects you to type
your edition's details in rather than pick it from a list, and picking
the edition is the main thing Goodreads' catalogue was for; the others
lack the data or are closed.

So opsimath becomes the catalogue. **Goodreads stays only as a place to
read about books Mark doesn't know** (ratings, reviews) — no data flows
from it, and changes there have been frozen since the sync stopped, so
there's nothing to catch up on.

Status: **design, not built.** Settled with Mark 2026-11-02; the probe
below is the evidence the provider choice rests on.

## Priorities

1. **Catalogue management, with the emphasis on editions** — this doc.
2. **Book discovery** — later.
3. **Social** — later still. BookWyrm's decentralised model is the
   appeal: opsimath could join that network over ActivityPub. Building
   opsimath's own backend rather than running BookWyrm (Mark: *"I'd
   prefer build here, but keep the option for integration into their
   network, which is the main benefit of their architecture"*). See
   *Keeping federation possible*.

## What the Goodreads sync was doing

| Goodreads did | Now in opsimath |
|---|---|
| New wishlist books arrived (wishlist shelf) | **Add to wishlist** |
| Wishlist → to-read = "I bought it": catalogue that edition, drop the wishlist entry | **Acquire**, from a wishlist book or from scratch |
| Currently-reading / read / DNF, with dates, rating, review | **Reading log** actions |
| The catalogue an edition was picked from | **Provider search**: ISFDB + Open Library |

Opsimath's model already holds every one of these states; what's
missing is the way in:

| Goodreads shelf | opsimath |
|---|---|
| wishlist | `WishlistItem` |
| to-read | an owned `Copy`, no `Reading` yet |
| currently-reading | `Reading` `reading` |
| read / did-not-finish | `Reading` `completed` / `dnf` (append-only: rereads are new rows) |

**Status changes are catalogue management, not part of the eBay
screens** (Mark: *"changing the status of a book between
wishlist/to-read/read/dnf is logically part of catalog management"*). The
bargain-hunting pages link to the book; the book's own page is where its
state changes.

## How Mark adds books

At the desk, going through the day's purchases — the Goodreads website
routine, not a phone app (Goodreads' app never had edition picking).
**Find the work, then pick which edition is mine from its list, mostly by
cover and publisher** — not printing or date.

## The two-step model

Agreed 2026-11-02 — opsimath's existing per-field provider model, with a
new front end, rather than merging providers into one edition record up
front (Mark: *"I prefer our current model of provider data from which
fields can be chosen to merge into our record… choose an edition, then
construct the record from fields from providers for that edition"*).

### Step 0 — find the work

Search by title/author (or ISBN). Each provider returns its own work
records — an ISFDB title, an Open Library work. Records that are
evidently the same work are shown as one result carrying all of them;
nothing is merged.

### Step 1 — choose an edition

The work's editions from every provider, **one card per publisher +
cover** — Mark's own choosing criteria, and the same grouping as the
wishlist cover picker (`WishlistCoverGrouping`). Provider records go on
one card when they're evidently one edition: a shared ISBN *and* the
same cover. ISBNs alone aren't enough — Orbit's 1977, 1979 and 1985
*Birthgrave* share one ISBN across two different covers. A pre-ISBN
edition gets a card per provider record; an occasional duplicate card is
cheaper than a wrong merge. Still nothing merged: a card is a bundle of
provider records.

### Step 2 — build the record

Picking a card creates the `Edition` (and the `Work`, if new); every
provider record on the card becomes one of its `EnrichmentRecord`s, and
fields are filled through the existing machinery — `FieldApplier`, field
sources, `PendingDecision` for genuine disagreements. So an edition can
be ISFDB + Open Library the way today's are Goodreads + ISFDB, and a
provider added later attaches the same way.

**Step 2 should mostly ask nothing at add time.** Fill empty fields
automatically, apply the trust rules already in place (authoritative
ISFDB covers, the publisher authority file), and leave only real
conflicts for the review queue. Picking fields by hand per book would
mean something upstream needs fixing.

### Then: what it is to Mark

The same screen ends with the intent: **wishlist**, **own** (a `Copy`;
"to-read"), **reading**, or **read** / **DNF** (a `Reading`, with
dates, rating and review). Acquiring a wanted book retires its `Want`
(`Want#retire!`, keeping the Work) and its bargain-hunting data with it. Buying from a `/finds` listing could
pre-select the printing that listing was identified as.

## Providers

Learnt from librarium's provider registry
(`librarium-api/internal/providers/`) — and from the ISFDB adapter,
which was written for it: each provider declares **capabilities**
(search works, a work's editions, ISBN lookup), and a registry fans a
request out to the providers that have it. Opsimath's version is
work-grouped — both ISFDB (title → publications) and Open Library
(work → editions) are naturally shaped that way — where librarium's
returns a flat list of edition records and merges fields up front.

- **ISFDB** (via isfdb-adapter, already used): `/search` (title +
  author, every edition of each matched title), `/isbn/{isbn}`,
  `/isbn/{isbn}/editions`. Best for SF: bindings, cover artists,
  printings.
- **Open Library** (new): `search.json` for works,
  `/works/{id}/editions.json`, ISBN lookup, cover images. Open data;
  asks for a descriptive User-Agent and gentle request rates. The natural
  first non-SF provider (Mark).
- **Goodreads**: not a provider — no API, and read-only by choice.

## The coverage probe (2026-11-02)

The question: for the books ISFDB *didn't* match by ISBN, can a title +
author search find them — in ISFDB, in Open Library — with editions to
pick from, including Mark's own? Run over every such book: 668 owned
works (a third of the 2,034 catalogued) and 88 wishlist books.

| | Owned (668) | Wishlist (88) |
|---|---|---|
| ISFDB finds the work by title + author | 369 (55%) | 31 (35%) |
| Open Library finds the work | 573 (86%) | 71 (81%) |
| **Either** | **615 (92%)** | **75 (85%)** |
| Open Library has an edition with a cover and a publisher | 532 (80%) | 60 (68%) |
| Mark's own edition (by ISBN) is in Open Library's list | 251 of 363 with an ISBN (69%) | 40 of 67 (60%) |

- **Open Library is the right second provider**, and not only for
  non-SF: it found 246 owned works ISFDB's search didn't; ISFDB found 42
  Open Library didn't. Median 8 editions per work (max 200).
- **ISFDB's search recovers much of what ISBN lookup missed** — 369 of
  the 668 — so the add flow should search both, not fall back.
- **The unfound 8% is mostly a search problem, not missing data**:
  anthologies credited to an editor (Aldiss's *Year's Best*, Derleth,
  Merril, *The Hugo Winners*), a curly apostrophe (*Cat’s Cradle*),
  retitled editions (*Aliens for Neighbors*). The search needs to match
  editors as well as authors, fold punctuation, and know alternate
  titles.
- **Books without an ISBN are fine**: 286 of the 305 such owned works
  were found by title + author.
- **74 owned books are in ISFDB under their own ISBN but unmatched** —
  every one is waiting on an `enrichment_printing_choice` in the review
  queue (103 of those pending, plus 317 field conflicts). Not a bug, but
  catalogue work the book page's edition picker is a better place for.

Probe script and cached responses are throwaway (scratchpad); the
numbers are what matter.

## Keeping federation possible

BookWyrm also separates Work and Edition and treats reviews as their own
objects, so opsimath's model lines up. Cheap to protect now: stable
public URIs for works, editions and reviews, and a clean Work/Edition
split. Not now: ActivityPub itself.

## Architecture review: aggregator → system of record (2026-11-02)

Mark asked whether the decisions so far still hold now opsimath moves
from aggregating Goodreads + ISFDB to being the system of record and
back office. Reviewed against the code and schema; agreed with Mark the
same day.

**Holds up — keep:** the Work / Edition / Copy split; the append-only
`Reading` log; per-provider `EnrichmentRecord`s with per-field
`field_sources`, where a provider only fills empty fields and every
overwrite goes to review (so Mark's edits are already safe from
providers); authority control; EDTF dates; paper_trail on Work, Edition,
Copy, Contributor, Series; the Rails monolith, Postgres, the services
layout, and the shop-lookup PWA's one-way snapshot.

**Built on aggregator-phase assumptions — change:**

1. **Backups — urgent, before data entry moves here.** Goodreads was the
   de facto backup: lost data could be rebuilt from it. Now it can't.
   Prod Postgres is on the NAS RAID over NFS (a Retain PV since the
   2026-09-06 prune incident), with no logical dump and nothing off the
   NAS — RAID covers a disk failure, not deletion, corruption, a bad
   migration or the NAS itself. Needed: nightly `pg_dump` + Active
   Storage blobs, retention, a copy off the NAS, a failure alert, one
   restore rehearsal. Infrastructure, so filed for the k8s side.
2. **The wishlist joins the catalogue.** `WishlistItem` was kept
   self-contained for two reasons (`docs/DATA_MODEL.md`): Goodreads'
   wishlist rule, and not committing to an edition before one is owned.
   The first is gone; the second is answered by putting the want on the
   *Work* — a wanted book is a `Work` with no `Copy`, plus a small want
   record (priority, notes, target price, chosen covers, buy-new
   override). Fixes the duplicated title/author, a separate add path for
   wishlist books, and "bought" being delete-one-model-create-another
   rather than adding a `Copy`.
3. **One per-work cache of provider-known editions.** The same thing —
   "the editions providers know for this work" — exists twice already
   (`WorkSiblingIsbns` for the shop app's scan matching,
   `WishlistPrinting` for bargain hunting) and the edition picker needs
   it a third time, now from ISFDB *and* Open Library. One table per
   work (provider, provider id, ISBNs, publisher, binding, date, cover,
   cover artist, cover group) serves all three. `editions` stays what's
   actually recorded; this table is the candidates.
4. **Work identifiers.** Editions have `edition_identifiers`; works have
   none — a work's identity is its title. The add flow must recognise an
   ISFDB title or an Open Library work as a book already catalogued, or
   it creates duplicates. A `work_identifiers` table mirrors
   `edition_identifiers`, and is what stable public URIs for federation
   would hang off later.
5. **Mark as a first-class source.** Values he types are `field_sources`
   `"manual"`, never re-raised as conflicts when a provider disagrees on
   the next fetch. Full paper_trail history on `Reading` (dates, rating —
   today only `private_notes`) and `Review` (today only `text`), since
   these are now entered here.

**Smaller:** the Goodreads importer, `ShelfSync`, `GoodreadsSyncState`
and `GoodreadsSyncJob` stay, dormant and labelled legacy; Goodreads ids
remain provenance. The review queue (420 pending) is more than Mark
works through; as the book page gains actions, a book's conflicts
belong on its own page rather than only in a global queue — revisit
then, not a blocker.

## Build order

Revised after the architecture review. Each step usable on its own and
checked against real data, as for bargain hunting. Steps 2–4 come before
the screens because those would otherwise be built on structures about
to change.

1. **Backups** (k8s side).
2. **Per-work known editions + work identifiers.** A refactor: the shop
   app's sibling-ISBN matching and bargain hunting's printings move onto
   the new table, verified by their output staying the same.
   **Built 2026-11-02** (the shop app's half; bargain hunting moves in
   step 4 with the wishlist): `provider_editions` and `work_identifiers`,
   filled by `Isfdb::WorkKnownEditionsRefresh` (since step 3, the
   per-provider `KnownEditionsRefresh`) for every catalogued work
   (not only owned ones); `WorkSiblingIsbns` dropped. On a production
   copy the shop app's sibling ISBNs came out identical for 2,031 of
   2,034 works — the other three each gained one printing ISFDB added
   since the old cache's last run. Found on the way:
   - ISFDB's editions list for a work also holds every omnibus and
     collection containing it, each reporting its own main title — so a
     work's ISFDB title id is taken only from its own printings (by
     ISBN). That gives 1,346 ids on 1,330 works; the only ids shared
     between works are 4 genuine omnibus cases, where the omnibus's own
     printing resolves to a novel inside it (*Peace and War* / *The
     Forever War*) — why the table isn't unique per id.
   - The omnibuses do stay in each work's known editions, as they always
     were in the shop app's ISBN index.
   - The editions call for a long-lived title (*The Lord of the Rings*,
     ~240 printings) can take over 10 s; it now gets 30.
3. **Provider registry + Open Library.** Capabilities (search works, a
   work's editions, ISBN lookup); ISFDB behind it; Open Library client;
   both filling (2); Open Library covers cached locally like ISFDB's.
   Searches run on submit, gently.
   **Built 2026-11-03:** `Providers` (registry; capabilities
   `:known_editions`, `:search_works`), `Providers::Isfdb`,
   `Providers::OpenLibrary` + `OpenLibrary::Client` (descriptive
   User-Agent, every request ≥ 1 s after the last, follows the ISBN
   redirect, paginates editions; cover URLs by cover id, which Open
   Library doesn't rate-limit, unlike ISBN-keyed ones), `Edtf.from_text`
   for Open Library's prose dates, and one `KnownEditionsRefresh` run per
   provider (per-provider due-ness in `provider_edition_refreshes`, which
   replaced step 2's two `works` columns). Covers are downloaded into
   Active Storage only when an edition is catalogued (steps 6–7). On a
   production copy, Open Library's first 30-minute run:
   - 293 works asked, 245 matched (84%); median 4 editions per work.
   - **0 of 191 works known to both providers share no ISBN** — no sign
     of a wrong Open Library match.
   - 54 works gained editions with no ISFDB ones; the shop app's index
     for owned works grew from 12,087 to 13,365 ISBNs (1,331 → 1,385
     works) — translations included, as in ISFDB's lists.
   - ~6 s per work (each ISBN lookup is two requests, misses retry up to
     three ISBNs, all paced), so the first pass over the catalogue takes
     about a week of nights; after that, monthly re-checks are ~70 works
     a night. The 30-minute budget keeps the run ahead of the 3:20
     snapshot.
   - Open Library has duplicate works (*Crossfire*: three) and duplicate
     editions (one Tor ISBN under "Tor" and "Tom Doherty Associates"),
     and 54% of editions have no format — for the add flow's grouping
     (step 6) to absorb, not to fix here.
   - Works without an ISBN aren't linked to Open Library yet — that needs
     title + author matching, which the add flow brings.
4. **The wishlist joins the catalogue.** The 339 items become Works
   (matched through the providers) with want records; bargain hunting
   and the shop app move across.
   **Built 2026-11-03.** `wants` (one per Work: priority, notes, target
   price, cover choices, buy-new override, the ISBNs it was wanted under
   as `seed_isbns`, the wishlist thumbnail, the legacy Goodreads id and
   `legacy_wishlist_item_id`); `contributors.died_date`/`life_checked_at`
   (life dates belong to the person — `Isfdb::ContributorLifeRefresh`
   replaces `WishlistAuthorRefresh`); `ebay_listings.work_id`. Bargain
   hunting reads a want's printings from its Work's ISFDB provider
   editions (`Want#printings`: physical ones), so `WishlistPrinting` and
   `WishlistPrintingRefresh` are gone; `KnownEditionsRefresh` seeds a
   wanted work's lookups from its `seed_isbns`. `Want.add!` is the one
   way to want a new book (Goodreads paths now; the add flow next). The
   nightly 2:50 job is `WishlistRefreshJob` (author life + cover
   grouping). The data migration converts in place and leaves
   `wishlist_items`/`wishlist_printings` untouched for a later drop.
   - **Matching to the catalogue:** a want joins an existing Work only
     when the item's ISBN is one of that work's *and* the short titles
     match — 6 of 340 did (*Counterweight*, *Fools*, *Voice of the
     Whirlwind*, …, all owned: upgrade hunts). ISBN alone would have
     merged 17 more wrongly: omnibus printings share ISBNs with the
     novels inside them (*The Blue World* with seven Vance works).
   - **Parity on a production copy:** for all 340, the rule, wanted
     printings, cover groups, author status, eBay listings, target price
     and cover choices are identical; Finds the same 19; the shop app
     334 wishlist entries + 6 owned works flagged wishlisted (was 340
     wishlist entries — the 6 are now the owned entry, as an owned-and-
     wanted book should be). A first version lost the author check for
     3 of the 6 (their work already had an author); fixed before deploy.
   - **Goodreads legacy:** buying a wanted book (wishlist → to-read)
     now catalogues the edition onto the want's own Work unless that
     exact edition is already catalogued — otherwise Matcher's
     title+author fallback would find the edition-less wanted Work and
     raise a reconciliation.
   - The shop app's thumbnail seeding (`MobileThumb.seed_from_snapshot`)
     is editions-only now: an older snapshot's wishlist entries are
     keyed by item ids, which aren't want ids.
5. **State changes on the book page** — reading log (started / finished
   / DNF, dates, rating, review), ownership (acquired / sold / given
   away), want (add, remove, acquire). The book page's job moves from
   reference to catalogue management.
   **Built 2026-11-03**, for books with an edition in the catalogue (the
   ~2,000 owned or read). Acquiring a *wanted* book, and logging a read
   of one, need its edition chosen first — the add flow (step 6).
   - **Reading log:** start (edition, date, own copy / library /
     borrowed); on the open read, finish (date, rating, an optional
     review saved as a draft — publishing it is punted), did not finish
     (date, reason), pause / resume; every past reading correctable, or
     deletable with a confirmation (its review stays). A finish before
     the start is refused. Reading and Review now keep full paper_trail
     history, not just notes and text.
   - **Copies,** under each edition card (the card itself is shared with
     the PWA, so it's untouched): add one (date, price, source,
     condition, notes), or record what became of one (sold, given away,
     lost, replaced).
   - **Wishlist:** add a book you have (an upgrade hunt), remove one —
     a wanted-only book's empty Work goes with it (`Want#retire!`, also
     what the Goodreads to-read path uses) — and a link to its bargain
     hunting.
   - **Books list:** each book's status (owned, wanted, reading, read,
     DNF) and filters by it — needed since step 4 made wanted-only books
     Works, which had put 334 of them among the owned books unmarked.
6. **Add a book** — search → work → edition cards (publisher + cover) →
   intent → step 2 enrichment.
   **Built 2026-11-03** (`/add`, "Add a book" in the header; a wanted
   book's page links to its picker as "I've got it").
   - **Search** (`AddBook::Search`): one box, title and author words
     together, or an ISBN (looked up, not searched). ISFDB and Open
     Library are asked together and their works grouped by short title
     + author surname. The providers match loosely ("hackers steven
     levy" brings back Steven Spielberg), so results are ranked by how
     many typed words are in the title (×2) and authors, and cut to 15.
     ISFDB titles whose known editions are all translations are left
     out. A book already catalogued says so — by stored provider work
     id, else by title + author — and offers "Add an edition" (or "I've
     got it" for a wanted-only book) instead of creating a duplicate.
   - **Want it** (6b): a new Work with its authors and provider work ids
     (`work_identifiers`), and a Want seeded with up to 3 ISBNs (for
     `KnownEditionsRefresh` that night) and the search cover. No
     edition.
   - **Edition cards** (`AddBook::EditionCards`): a catalogued work
     reads its `provider_editions` (no network); a new one fetches live
     (ISFDB by ISBN, else the printings the search returned; Open
     Library by every work id — OL keeps duplicate works for one book).
     ISFDB printings share a card on the same scan, or the same ISBN +
     cover artist under one publisher (DAW's *Birthgrave* is in ISFDB
     twice, once undated, with two scans of George Barr's cover); Orbit's
     1977 and 1979/85 covers, one ISBN, stay apart. An Open Library
     edition joins the ISFDB card with its ISBN only if exactly one has
     it. Other-language editions are hidden behind a link; ebook and
     audio sort last. What a page offers travels to the next request as
     a signed token (1 day), so saving needs no second lookup — a
     pre-ISBN printing couldn't be looked up again.
   - **The record** (`AddBook::Create`): the card's ISFDB record (the
     printing with a cover and a date) fills the new edition through
     `SourceRecorder`; the other providers' records are stored beside
     it and **fill only the gaps** (Open Library's cover for a printing
     ISFDB has no scan of) — never a conflict, so adding a book adds
     nothing to the review queue (verified: 420 before and after).
     Identifiers: ISBN-13/10, ISFDB pub id, Open Library edition id.
     Then a Copy ("I own a copy", on by default), and optionally a
     Reading — reading now, or read with a finish date and rating.
     Getting a wanted book retires its want and keeps the work.
   - **Found on the way:** `HasCoverImage.fetch_image` didn't follow
     redirects, and every Open Library cover id redirects to
     archive.org — so OL covers were silently dropped everywhere,
     including cover grouping and eBay printing identification once OL
     rows have covers (none had yet). It follows up to 3 now.
   - **Not yet:** DNF from the add screen (log it on the book page);
     the review text on finishing; pre-selecting the printing from a
     `/finds` listing; editing a new work's literary form (always
     "novel" — change it on the book page later).
7. **Edition picker for existing books** — change which edition you
   own, and settle queued printing choices there.
   **Built 2026-11-03.** Every edition on the book page has "Not this
   edition?"; one with a queued `enrichment_printing_choice` also shows
   "Several printings share this ISBN. Which is yours?" (conflict
   colours). Both open the add flow's card grid for that edition
   (`EditionChangesController`, `/works/:id/editions/:id/edit`): the
   work's known editions plus the decision's own candidates, the current
   printing ("Yours now") and same-ISBN cards first.
   - **Choosing is an identity call** (`EditionChange`), like accepting a
     printing choice (`IsfdbEditionEnricher#commit_choice`): the edition
     *becomes* that printing — bibliographic fields, cover, ISBN and
     ISFDB / Open Library identifiers and records are cleared and the
     card fills it as if new (`AddBook::Create.fill`). A printing with no
     cover leaves none rather than keeping the old printing's. Copies,
     readings, Goodreads identifiers and records, and manual fields
     outside the bibliographic set stay.
   - **Queued decisions are settled first:** the printing choice
     accepted; ISFDB / Open Library field conflicts rejected as moot
     (they compared another printing). Goodreads conflicts stay.
   - **Real data (UAT):** Foundation and Earth's 7 queued printings are
     3 same-ISBN cards among 21; Fahrenheit 451's 12 are 5 — printings
     without a scan or artist stay a card each, since nothing says which
     cover they had. Each choice took one off the queue.
   - **Found on the way:** on a card holding several printings from one
     provider, the other printings were stored as that provider's
     "second" record, overwriting the chosen one — so the ISFDB
     identifier and record named different pubs. Fixed in step 6's code
     too; the one book added on prod since was unaffected.
   - Owned works' known editions arrive with the nightly refresh (none
     yet on prod: tonight's 2:40 run is the first since step 2); until a
     work has them the picker fetches from ISFDB by its ISBN.
8. Later: discovery; then federation. Reviews' route to scifipraxis is
   punted — posting to Goodreads was manual anyway, so nothing is lost.

## Settled (2026-11-02)

- **Reviews:** later. Posting to Goodreads was manual, so nothing is lost
  meanwhile.
- **Open Library covers:** cached locally, the same as ISFDB's.
- **Search:** submit-to-search, gentle on Open Library; must match
  editors and alternate titles, and fold punctuation.
- **The book page** becomes catalogue management (its job changes from
  reference, `docs/UI_PRINCIPLES.md` principle 2).
