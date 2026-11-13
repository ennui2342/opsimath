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

*Since 2026-11-03 the edition is anchored to one primary printing rather
than merged across providers — see "Anchored editions: one primary
printing". The add flow itself is unchanged.*

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
   - **No "copies" in the interface** (2026-11-02, Mark): every edition
     has exactly one Copy in practice (2,055 of 2,055), so the book page
     talks only about editions. Under each card, one collapsed panel
     (`works/_edition_panel`): *This edition is* Owned / Sold / Given
     away / Lost / Replaced / Not mine (read from a library or borrowed —
     an edition with no Copy), with purchase details (`EditionHolding`,
     the Copy behind it); "Not this printing?"; and, when the book has
     another edition, *Delete this edition — added by mistake*
     (`EditionRemoval`): its readings move to an edition kept or go too,
     reviews stay with the book, queued decisions close. Getting rid of a
     book is its status, never a delete. Editions are opsimath's own
     records built from the providers' (see "The two-step model"), so a
     duplicate is deletable; the providers' records aren't touched.
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
   - **"This edition is"** (2026-11-02, Mark): the add flow's ownership
     choice matches the Goodreads edition-reconciliation decision's —
     *Mine* (alongside any already owned: "add edition"), *Mine — it
     replaces my <edition>* (that one becomes Replaced: "change
     edition"), or *Not mine — read from a library / friend / elsewhere*
     ("unowned read"; the reading's source). "Relink" is Goodreads-only;
     a wrong printing on file is the book page's "Not this printing?".
   - **Barcode scanning** (2026-11-02): "Scan barcode" beside the search
     box (`barcode_scan_controller.js`, the PWA scanner's twin) reads an
     EAN-13 with the browser's `BarcodeDetector` and submits it as an
     ISBN lookup. Shown only where the browser has one (Chrome on
     Android / macOS, not Safari). Browsers only offer the camera to a
     secure page, so on the plain-HTTP internal address
     (opsimath.k8s.ecafe.org) the button goes to the same page on the
     HTTPS Tailscale address (`config.x.public_url`) with `?scan=1`,
     which opens the scanner on arrival.
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

## Anchored editions: one primary printing (design, 2026-11-03)

**Status: agreed with Mark 2026-11-03, not yet built.** Supersedes the
multi-source field merge described in "The two-step model", step 2, for
how an edition's fields are kept — not for how a book is added.

### Why

The enrichment machinery (per-provider `EnrichmentRecord`s, `FieldApplier`
planning each field, bundled `PendingDecision`s for disagreements) was
built when Goodreads was the source of truth and ISFDB the enrichment:
every disagreement needed a referee. Two things have changed.

1. **Many "conflicts" were identity conflicts in disguise.** Goodreads
   described one printing, ISFDB another (reused ISBNs, reissues), and
   merging fields across them made editions that describe no real book —
   Fahrenheit 451 with one printing's cover and another's date. Printing
   choice (2026-09) and "Not this printing?" (step 7) were already moves
   away from merging.
2. **Goodreads is gone, and ISFDB is the better data.** What's left of
   the merge model is mostly a review queue Mark can't clear without
   digging books out to check them by eye.

Mark asked the decisive question: what does all the cross-provider
reconciliation actually *gain*? Looking at what the data is used for:

| Used for | Needs | Manual work |
|---|---|---|
| Shop app: owned? which printing? another printing's barcode | the book's ISBNs, any provider | none — automatic |
| Bargain hunting, covers, new printings | ISFDB's printing list per book | none — automatic |
| Book page: the edition's cover, publisher, date, artist | one good record of the printing | one choice, at add time |
| Review queue | multi-source field merge | all 417 decisions |

The valuable part — book-level links — is automatic. The manual burden
is all in merging fields per edition. Librarium never tried this: it used
providers to identify your edition and left it there. That, plus
automatic background links, is the model.

### The model

1. **Each edition is anchored to one primary printing**: the ISFDB
   publication where ISFDB has the book, else the Open Library edition.
   With neither, the edition stands on its own — Mark's values and any
   legacy Goodreads values.
2. **The primary's fields are trusted.** Refreshes follow its link and
   update quietly — no review decisions. If ISFDB adds a cover scan or
   corrects a date, it arrives.
3. **Mark's manual values always win** (`field_sources` "manual"); no
   refresh touches them.
4. **Other providers only fill gaps**, and only when matched to the same
   printing (a unique shared ISBN, or a cross-reference id). They never
   overrule the primary and never raise a conflict; if the primary later
   gains a value, it replaces the gap-filler quietly. Useful, not
   essential (Mark).
5. **What stays manual** is only a genuine "which printing is this?" — a
   reused ISBN across covers, or the evidence below that the anchor is
   the wrong printing — and Mark can leave those until he cares about the
   book.

The edition is still opsimath's record — anchored, augmented, correctable
— not a copy of the provider's. It's narrower than "best of every
record", deliberately: that's the version that stays up to date without a
referee.

### Book-level links (automatic)

What providers know about a *book* (`work_identifiers`,
`provider_editions`) is kept by `KnownEditionsRefresh` as now, but as a
reconciliation loop rather than a one-off ISBN lookup, the same for every
provider:

1. **Gather evidence**: the book's edition ISBNs, its want's seed ISBNs,
   every ISBN any provider has already given for it, any provider ids
   already stored.
2. **Each provider identifies the book**, strongest evidence first:
   a stored id; a cross-reference id another provider recorded (Open
   Library editions often carry Goodreads ids — every edition has one —
   and ISFDB publications can carry Open Library ids; *measure the yield
   before relying on it*: ISFDB's identifier table was real but low-yield
   in September, `non_isbn_enrichment_dead_ends`); an ISBN; then title +
   author through **one shared matcher**. A provider only supplies *how
   to search*; what counts as a match lives in one place.
3. **Repeat once** when a new link appeared — a link brings ISBNs, so
   "found by Open Library" becomes "found by ISFDB".
4. **Unlinked books stay due** (weekly), so a book a provider adds later
   is picked up then; a book Mark adds that no provider has is simply
   unlinked until one does.

The shared matcher is today's ISFDB title fallback generalised: folded
short title + author surname; records with no English printing dropped
(same-titled translations); an exact full-title match preferred
(adaptations); identical English records taken together (one book
credited two ways); anything else ambiguous takes nothing. Measured on
ISFDB: 19 of 25 previously unfound, all correct (see "ISFDB by title").

New printings arrive on a book's printing list as providers add them —
worth surfacing later ("a new printing of a book you want").

### Editions follow their anchor

An edition's anchor is its provider identifier: an `isfdb` (pub id) or
`openlibrary` `EditionIdentifier`. Already true for 1,387 of 2,060
editions (ISFDB). For the rest: a unique ISBN match among the book's
`provider_editions`, else a printing choice. Once anchored, each refresh
re-applies the anchored record through `SourceRecorder` under the rules
above — fills, and quiet updates of fields the primary supplied — instead
of today's one-shot `IsfdbEditionEnricher` (ISBN-only, ISFDB-only, run
once per edition and never again).

### Authority stays shared

The publisher authority file is already provider-neutral: one preferred
name per publisher, collecting variant spellings from any source —
Goodreads, ISFDB, Open Library, Mark. That's the library norm (the
Library of Congress name authority file: one record, all its forms;
VIAF: national authority files clustered into one identity). Only the
`/settings/authorities` preview compares against ISFDB's spelling
specifically; it should take any provider's.

### Where the code is ISFDB-specific

| Area | Now | Plan |
|---|---|---|
| Edition enrichment (`IsfdbEditionEnricher`) | ISFDB-only, one-shot | generic anchored refresh; ISFDB's *rules* (publisher variants, EDTF precision) kept as its rules |
| Printing choice decisions | raw ISFDB candidates | stays ISFDB (the printing-level provider), raised by the anchoring step |
| Title fallback (`Providers::Isfdb#by_title`) | ISFDB-only | the shared matcher, every provider |
| Author alive/dead (`Isfdb::ContributorLifeRefresh`) | ISFDB-only | any provider with author dates (Open Library has them) |
| Authority preview | ISFDB's publisher | any provider's |
| Bargain hunting (`hunted_printing?`, eBay `matched_pub_ids`, cover groups) | ISFDB printings only | **kept, deliberately**: only ISFDB has bindings (A/B-format) and cover artists. Later, a provider-neutral "printing" so another source could feed it |
| Goodreads importer / `ShelfSync` | legacy | frozen; Goodreads ids stay as provenance and a cross-reference |

### The existing queue

Measured 2026-11-03 (prod copy): 417 pending — 313 ISFDB field
conflicts, all on editions already anchored to an ISFDB printing; 103
printing choices; 1 Goodreads conflict.

Every one of the 313 is held up by only 1–3 real disagreements, in four
fields; everything else in them is ISFDB filling an empty field, held
hostage by the bundle:

| Field | Real disagreements | Fills | Typical |
|---|---|---|---|
| publish_date | 283 | — | "1990" (Goodreads) → "1990-02" |
| publisher | 277 | 1 | "Littlehampton Book Services Ltd" (a distributor) → "Magnum"; "Futura Orbit" → "Orbit" |
| cover_image | 36 | 216 | (51 identical) |
| format | 9 | 1 | "paperback" → "hardcover" |
| page_count / language / cover_artist / format_detail | 0 | 310 / 290 / 230 / 128 | — |

Date disagreements by size: 221 same year (ISFDB only more precise), 27
one year, **35 two or more years** — mostly the anchor being the wrong
printing of a reused ISBN (NEL *The Dragon in the Sea* 1969 vs 1979,
Sphere *Babel-17* 1969 vs 1977).

**Policy**: ISFDB wins for anchored editions. Resolve automatically,
accepting ISFDB's values, **except** a decision whose date differs by 2+
years or whose format differs — an identity question, not a data-quality
one. Those (~40) go to Mark as "which printing is this?", reached from
the book page; the rest (~270) close. The 103 printing choices stay
Mark's, to do lazily. Before applying, re-run this breakdown on prod and
spot-check examples per field.

### Build order

1. **Queue policy**: auto-resolve the ~270, re-raise the ~40 as printing
   questions. Immediate relief, and the rule the new model enforces
   anyway.
   **Built 2026-11-06** (`ReviewQueue::IsfdbWins`, `rake
   review_queue:isfdb_wins` — dry run unless `APPLY=1`). Accepts through
   the review screen's own path; flags the rest with payload
   `identity_question` — the book page then says "ISFDB's record looks
   like a different printing: ISFDB's printing is dated 1979; yours 1970.
   Which is yours?" and links to the edition picker. UAT trial on the prod
   copy: 274 accepted, 42 flagged, 1 Goodreads rejected; 418 → 143
   pending (42 + the 101 printing choices), 3 seconds. The publisher
   authority file is empty on prod, so ISFDB's spelling is what lands.
   **Applied on prod 2026-11-06** (Mark's go-ahead; verified backup
   `tmp/opsimath-prod-pre-queue-policy-20261106-113137.dump`): 270
   accepted, 1 rejected, 42 flagged — 418 → 145 pending (42 printing
   questions + 103 printing choices).
2. **Shared matcher + reconciliation loop** for book-level links (every
   provider; cross-reference ids measured first; repeat-once; weekly
   retry for unlinked). Replaces the ISFDB-only fallback.
   **Built 2026-11-06**: `WorkMatcher` holds the rule (plus ignoring a
   leading article — Lem's "Futurological Congress" is ISFDB's "*The*
   Futurological Congress" — and name suffixes, "Kurt Vonnegut, Jr.");
   `KnownEditionsRefresh` asks each provider by id or ISBN, then — when
   that finds nothing — by its own `search_works(complete: true)`. A
   book's ISBNs include up to 5 that *other* providers gave, English
   printings of the book itself only; new ones change `queried_isbns`, so
   the book is re-asked — that's the repeat. Unlinked books are retried
   weekly for every provider (`UNLINKED_RETRY`). Open Library follows
   every stored work id (up to 4 — it keeps duplicate works). Measured on
   books each provider hadn't found: ISFDB 16/20 by title (~11s each),
   Open Library 17/20 (~3s each) — including non-SF ISFDB will never have
   (Berger's *Ways of Seeing*). **Cross-reference ids measured and
   dropped** (2026-11-07): Open Library found 3 of 30 unlinked books by
   Goodreads id (`id_goodreads`), all ordinary titles the title search
   finds anyway — not worth a step. Open Library's lists include translations; harmless — the
   picker hides them, cross ISBNs take English only, bargain hunting
   ignores Open Library.
3. **Anchored edition refresh**: primary trusted, manual wins, gap fill
   from matched secondaries; retire `IsfdbEditionEnricher`'s fetch path.
   **Built 2026-11-07** (`AnchoredRefresh`, `AnchoredRefreshJob` nightly
   at 03:30 after the printing lists; `rake anchored_refresh:plan` dry
   run / `:apply`). Reads the anchor from `provider_editions`, no network.
   Dry run on prod changed the plan in one way: **trust is per provider.**
   ISFDB anchors fill, update and replace; **Open Library anchors only
   fill** (and update what they supplied) — their replacements weren't
   better than what was there: group names for imprints ("Orbit" →
   "Little, Brown Book Group Limited"), exact-day dates ("1967" →
   "1973-08-12"), guessed formats. Metadata-cog picks are now sourced
   "manual", so the refresh never overrides a hand choice (Mark: the cog
   stays the way to finesse a field). Measured: 1,222 editions anchored to
   ISFDB, 201 anchorable by a unique ISBN (200 Open Library), 145 held,
   128 ISFDB-linked with no stored record (to look into), 367 with no
   anchor. Changes: 155 ISFDB publisher spellings ("Tor Books" → "Tor",
   "GOLLANCZ" → "Gollancz"), 10 other ISFDB fills/updates (Mirrored
   Heavens' ISFDB cover scan), ~436 Open Library fills (153 page counts,
   150 languages, 125 covers for editions with none). Each edition
   changed is one line in the 04:30 #catalogue digest.
   **First run (2026-11-08 03:30): 353 editions changed in 4 minutes.**
   Two follow-ups the same day: (a) the digest's "new printings" announced
   411 across 96 books — nearly all old printings newly *seen* by us after
   the week's lookup changes, not new to ISFDB — so only newsworthy ones
   are announced now: for a wanted book, any physical non-book-club
   printing (a new cover to hunt); otherwise one from this year or last.
   (b) the 128 "linked but no record" editions were 132 books isfdb-adapter
   won't build a printing list for — anthologies, nonfiction, magazines
   ("isbn found but not linked to a book-type title"); the provider now
   falls back to the plain ISBN lookup and stores that one publication, so
   the edition has its anchor record.
4. **Authority preview from any provider.** (Author dates stay
   ISFDB-only — Mark, 2026-11-07: the living-author rule is now a switch
   he expects to turn off; see docs/BARGAIN_HUNTING.md.)
   **Built 2026-11-08**: the `/settings/authorities` preview checks a
   provider's record of each edition — ISFDB first, then Open Library —
   and says which; not Goodreads, usually where the value came from.
5. *(Later)* Surfacing new printings; a provider-neutral printing for
   bargain hunting.
   **New printings, built 2026-11-08**: the 04:30 digest stars wanted
   books' newsworthy printings, and a bargain-hunting cover card says
   **New** for 30 days when one of its printings was announced
   (`WishlistItemView::Cover#new`, from the `new_printings` events' pub
   ids — not from when a row first landed, so this week's catch-up didn't
   make every cover "new").
   **Provider-neutral printing: deferred, deliberately.** It pays off only
   when a second source has bindings (A/B format) and cover artists, and
   none does — Open Library's formats are the guesses step 3 declined to
   trust. Reworking eBay `matched_pub_ids`, cover groups and overrides
   now would change nothing visible. Revisit if a provider with
   printing-level format and artist data is added.

## ISFDB by title when there's no ISBN (2026-11-03)

Mark wanted *The Fifth Head of Cerberus*; its bargain page said ISFDB
had no printings. His copy (Gollancz 2004) has only a Goodreads id, and a
want added from the book page has no seed ISBNs, so the refresh had
nothing to ask ISFDB with — though ISFDB lists 21 printings (title 1957).
`Providers::Isfdb#known_editions` now falls back, when no ISBN resolves,
to a title + author search: the one ISFDB title whose folded short title
and author surname match — none or several and it takes nothing — with
the printings the search lists for it (an ISBN lookup from one of them
wandered into the series: Calder's *Dead Boys* pulled in *Dead Girls*).
ISFDB often keeps several records under one title and author —
translations that kept the title (*Lexicon* in German and Dutch),
adaptations (*Kindred: A Graphic Novel Adaptation*), the same book
credited two ways (Brian / Brian M. Stableford's *The Paradise Game*) — so
records with no English printing are dropped, an exact full-title match
is preferred, and identical English records are taken together. The
adapter's search `limit` counts rows, not titles: at 60, *The Dragon in
the Sea* was cut off entirely, so the fallback asks for 500 (and Add a
book's search for 300).

On a 25-book sample of works ISFDB hadn't found by ISBN: 19 found, all
correctly (~9s each). The 6 left are right to be left: an NEL split
volume ISFDB doesn't record (*The Past Through Tomorrow: Vol. 2* — it
must not take Vol. 1), two editor-credited anthologies the search doesn't
surface, two non-fiction books outside ISFDB, and one Goodreads
mis-import (sheet music, "DAYS OF GLORY CONCERT BAND/HARMONIE/FANFARE",
for Stableford's *The Days of Glory*). Works found empty before this are re-asked on
the next run (`TITLE_FALLBACK_SINCE`), then weekly as usual.

Wanting a book (book page, or "Want it" in Add a book) now runs
`WantPrintingsJob` straight away: its printings fetched and covers
grouped, so the bargain page fills in within a minute, not overnight.

## ISFDB links from editions (2026-11-13)

A book (Work) is linked to ISFDB *titles*; an edition is anchored to one
ISFDB *printing* (publication). The two must agree: **a book's ISFDB
titles are the titles its editions are printings of.**

Until 2026-11-13 they could disagree. Links were learnt from ISBNs — the
edition's ISBN found a printing, and the printing was asked its title —
and isfdb-adapter answered with the first book-length title in the
printing's contents. An omnibus printing contains the OMNIBUS title and
each novel in it, so it was often credited to a novel. The wrong link then
drove everything that trusts it: Peace and War was renamed The Forever War
(TitleCleanup), typed a novel (Isfdb::MainTitles), and merged into the
novel as a duplicate. Code had grown around the symptom — string-matching
"own printings", heuristics picking the right one of several links, a
pruning pass — instead of fixing the cause. Reviewed with Mark the same
day; the fix:

1. **isfdb-adapter**: a printing's title is the one of its own type
   (`pubs.pub_ctype`) — an omnibus printing is the omnibus's.
2. **Each printing keeps its own title** (`provider_editions.provider_work_id`),
   so a book's own printings are exact (`Work#own_isfdb_printings`, used
   by AuthorLinks and WorkSeriesSync), not judged by title.
3. **Links come from editions** (KnownEditionsRefresh): an anchored
   edition gives its printing's title; an edition not yet anchored, its
   ISBN's (an ISBN can be reused — anchoring settles which). The
   provider's own title search stands only when no printing is the book's.
4. **Existing links reconciled** (Isfdb::LinkReconcile, `rake
   isfdb:reconcile_links`, dry run first): links no edition supports are
   dropped and remembered as `isfdb_title_rejected`; missing ones added;
   a title taken from a dropped link goes back to the book's own. An
   edition whose title was rejected before is a conflict for Mark — the
   anchor may be the wrong one — and nothing changes on it. Replaces
   TitleLinkPrune.
5. **Merging** refuses two books whose editions are printings of different
   titles (WorkMerge), whatever links they share.

Left until the reconciliation has run: simplifying Isfdb::MainTitles'
choice among several links (chapbook last, container first, …), which
only books not yet anchored should need.

## Author, series and publisher pages (2026-11-08)

Linked from the book page: each author's name (`/authors/:id`), each
series (`/series/:id`), and each edition card's publisher (`/publisher?
name=`). An author page lists their books in publication order, other
roles (editor, translator) apart; a series page in series order,
numbered — so a gap shows (the Culture without *Use of Weapons*); a
publisher page the editions under that imprint, its spellings taken
together the way the edition picker groups them ("Panther" 48, "Panther /
Granada" 12, "Panther Books" 9). Each row carries the book's statuses
(`works/_book_list`, shared with the Books list).

**Publication series** — a publisher's branded line, numbered within it
(The Women's Press Science Fiction; the SF Master Series, ISFDB pub series
579) — are ISFDB's third kind, distinct from publisher and story series;
it's what Mark collects as a set and would want as a whole. isfdb-adapter
39814fc returns each printing's line and number and `GET /pubseries/{id}`
(deploy task ed9d4f02); line pages, and wanting a line, follow.

**Cover artist pages** (`/artist?name=`), since Mark collects for the
covers: a grid of his covers by the artist (owned or not, linked to the
book), their covers on books he wants (linked to bargain hunting), and
whether they're a favourite, and their covers on books he *has* but
isn't hunting — other printings, one tile per distinct scan, each with
**Want this cover**: the book onto the wishlist hunting just those
printings (`printing_override_ids`), an upgrade hunt. Both the artist
page and the bargain-hunting cover picker show the covers
`CollectingProfile#offered_printings` gives — the collecting rule's by
default, every physical printing (book clubs aside) behind a **Show all
formats** switch on each (Mark: the two displays should match). Choices
made in the all-formats view survive saving the rule's view. Keyed by name — cover artists are names on
editions, shared credits ("A, B") split. Linked from edition cards,
bargain-hunting cover cards and finds.

Data note, fixed 2026-11-08: the Goodreads import recorded cover artists
as co-authors (*Slan* — van Vogt, Chris Foss). `MisfiledArtistCleanup`
moved 103 such credits off books: 85 ISFDB credits with that book's
cover, 18 known cover artists who are never a lead author (Keith
Roberts, who also wrote, left alone); the name moved to the edition's
cover artist where that was empty; artists left with no books removed.

**ISFDB outranks an Open Library link** (2026-11-08, Continuum 4): an
edition's anchor is its ISFDB identifier, else the single ISFDB printing
its ISBN identifies — even when it's already on Open Library, since ISFDB
is the trusted source — else Open Library. Two ISFDB printings on one ISBN
leave an Open Library edition where it is. A book just added has its
printings looked up and its editions refreshed at once (BookAddedJob), not
overnight. isfdb-adapter@12e7172 counts ANTHOLOGY and NONFICTION titles as
books, so anthologies appear in search and get printing lists.

**Series from ISFDB** (2026-11-08, The Snow Queen Cycle): series came
only from the Goodreads import and Add a book set none — The Snow Queen
and World's End sat outside their cycle (538 of 2,376 books in a series).
Each ISFDB printing now keeps its title's story series and number
(`provider_editions.series_*`; isfdb-adapter@afa1388 adds the name).
`WorkSeriesSync` files a book in it: the series tied to that ISFDB series
(`series.isfdb_series_id`), else one of the same name (then tied), else a
new one, with ISFDB's number (0 = unnumbered). It adds memberships and
fills empty positions, never changes or removes either. Not matched by the
series a book's siblings are in — ISFDB's sub-series (Rincewind within
Discworld) would mis-tie a Goodreads series. Runs for a book just added
(BookAddedJob), and nightly over the whole catalogue after the 02:40
printing refresh (Mark approved the dry run, 2026-11-09: 443 books, 96
into existing series, 347 into 242 new ones). A series also matches by a
near name — one holding the other word for word ("Confluence" / "The
Book of Confluence") with its books in that ISFDB series (books ISFDB
files in none don't count). The digest reports filings as a count and a
sample.

**Cover proxy** (2026-11-12): ISFDB's image server trickles each cover
out at ~3 KB/s per connection (19–27s each), so the edition picker took
most of a minute. Every provider cover on a page now goes through
`/cover?u=` (CoversController, `cover_src` helper; known cover hosts
only): a cover in the cache (HasCoverImage, storage/cover_cache on the
volume web and worker share — the 2026-09-05 rebuild's cache, never
switched on for the running app until now) is served from disk with a
year's caching; a miss sends the browser to the provider as before while
CoverCacheFetchJob fetches it in the background. CoverCacheWarmJob (05:00)
fetches up to 300 a night, one at a time, of the covers of books Mark owns
or wants — never in bulk: ISFDB is volunteer-run.

**A book's title is ISFDB's main title** (Mark, 2026-11-10): the title
of first publication, as a book added from ISFDB gets — library practice's
preferred title of the work; an edition printed under another title says
so on its card ("as Voyage to Venus"), and a replaced title stays as an
alternate title, which search covers. Each linked book's main title and
variants come from isfdb-adapter `/titles/:id` (Isfdb::MainTitles,
nightly, monthly per book). TitleCleanup sorts differences into brackets,
cosmetic, variant (one of its variant titles), reworded (shares words)
and suspect (shares nothing — likely a wrong ISFDB link, never retitled).
Mark approved all but suspect as automatic (dry run: 52 brackets, 128
cosmetic, 58 variant, 71 reworded), applied nightly; the main title is
the English one (for a translation ISFDB's main title is the original's),
volume-number mismatches and no-letter ISFDB titles excluded. A suspect
book becomes a pending decision, "Wrong ISFDB link?" (`title_link_question`):
choose the right printing, take ISFDB's title, or keep Mark's — under
Pending decisions, not Settings (Mark: it's a decision about a book).
Earlier the same day, before main titles:

**Titles from ISFDB** (2026-11-10): a book's title is the book's, so
choosing an edition never changed it. For books linked to ISFDB, the
title follows ISFDB's (the one most of its printings carry) nightly when
the difference is only a bracketed Goodreads note or cosmetic (capitals,
punctuation, "&", a leading article) — Mark approved the dry run: 50 + 122
books (TitleCleanup). Anything worded differently (UK/US titles,
subtitles, or a book linked to the wrong ISFDB record — Kesrith → The
Faded Sun Trilogy) waits in Settings → Titles to review: take ISFDB's,
keep mine, or choose the right printing. The cog has a Title section
(sources' titles, or Mark's own); a title Mark sets is "manual" and never
changed or listed again.

**Wanting an edition in better condition** (2026-11-09): an owned
edition's panel on the book page has "Want this edition in better
condition" (BetterCopy): the book onto the wishlist hunting exactly that
printing (its ISFDB pub id in `printing_override_ids`); a book already
wanted keeps what it hunts and gains the printing. Needs the edition
linked to its ISFDB printing. Worded without "copy" — the interface talks
in editions.

**Scanning US mass-markets** (2026-11-08): many US mass-market
paperbacks carry a retail UPC instead of an ISBN barcode. The UPC names
only the publisher (digits 2–6) and cover price, shared by every book at
that price. The 5-digit add-on beside it is, by the publisher's
convention, ISBN-10 digits 5–9 (Tor: 0-8125-5010-2 → 55010) or the
ISBN's title part zero-padded (DAW: 0-88677-299-0 → 00299, found
2026-11-13 — publisher code lengths from the ISBN ranges,
`Isbn.publisher_prefix`); isfdb-adapter `/isbn/addon/:digits` tries both,
and UpcPrefix learns each UPC publisher's real ISBN prefixes — several for
some (Tor's UPC 037145 is 0812 and 0765) — seeded 2026-11-13 from
LibraryThing's UPC vendor → ISBN vendor table (wiki.librarything.com,
"ISBN" → "UPC to ISBN conversion", 40 entries), which also confirms digits
5–9 as the usual convention (it lists DAW as 0886).
Both scanners (web `barcode_scan_controller`, pocket `pocket.js`) read
through `app/assets/mobile/scan.js` — zxing-cpp in WebAssembly (zxing-wasm
3.1.6, served from our assets and cached for offline), because the
browser's BarcodeDetector can't read add-ons (nor exists in Safari). A
UPC + add-on is searched as "UPC add-on" (`UpcLookup`): isfdb-adapter's
`/isbn/middle/:digits` gives the printings with that middle, English and
physical ones kept; there's no published table of UPC publisher codes, so
`UpcPrefix` learns each one — a scan's candidate ISBN prefixes narrow the
publisher's until one is left (and the pocket snapshot carries the learnt
ones). Until then every candidate is offered. If the camera gets the UPC
but not its add-on in ~3s, the UPC goes in the search box for the five
digits to be typed. Offline, pocket matches the add-on against the
snapshot's own ISBNs.

**Author pages list their whole bibliography** (2026-11-08): an
author linked to ISFDB shows every English book-length title of theirs
in its own right (no retitlings or translations), grouped Novels /
Collections / Anthologies / Non-fiction / Omnibuses / Chapbooks, beside
the catalogue's books — "Want it" and "Add" for those Mark doesn't have.
The bibliography (isfdb-adapter `/authors/:id`, up to ~30s to build) is
kept on the Contributor (`isfdb_works`), fetched in the background when
the page is visited and missing or a week old. Authors were linked to
ISFDB only as a side effect of the living-author check, which looked up
wanted books' authors alone (247 of 1,224); it now covers every author,
wanted books' first, and visiting an unlinked author's page links them.
The artist page's ★ makes an artist a favourite or not, overriding the
owned-covers rule either way (the always / never lists).

**Authors linked through their books** (2026-11-08): each ISFDB
printing keeps its credited authors with their ISFDB ids
(`provider_editions.author_names/author_ids`; isfdb-adapter@d925a6b).
`AuthorLinks`, nightly after the printing refresh, links an unlinked
author when their books' own printings credit them by name with one id —
or, for a sole-author book credited under another name (a pseudonym, a
spelling), when two or more books agree. An author already linked by name
to a different id is reported (`AuthorLinks.plan`), not changed. A
linked author's life dates are then read by id; name search stays the
fallback.

**Removing a book** (2026-11-08, two Books of Blood): "Remove this book
from the catalogue…" at the foot of the book page (WorkRemoval) deletes
the work and its editions — for a duplicate or a mistake; getting rid of
a copy stays a status change. An edition another book shares only loses
its link. Readings and reviews move to another book by the same author,
or readings are deleted; a book with reviews must move them — a review is
never deleted with its book. Queued decisions close as moot.

**Series pages** (2026-11-08): a series tied to ISFDB (or whose books'
printings all name one ISFDB series) lists every book-length title ISFDB
files there (isfdb-adapter `/series/:id/volumes`, cached a day; other
languages' omnibuses left out) beside the catalogue's own members, in
series order — Mark's numbering where he has one. A book he doesn't have
gets **Want it** (into the catalogue, the series and the wishlist) and
**Add**. **Collect this series** is a `SeriesWant`, synced with the line
wants at 02:30: every book he doesn't own or want becomes a want for the
book (not a printing); "Not this one" sticks; stopping removes only its
wants. The publisher page lists the publisher's lines, a way into them.

**Publishers' lines** (built 2026-11-08): each stored ISFDB printing
keeps its line (`provider_editions.pub_series_id/_name/_num`); the book
page shows an edition's line ("The Women's Press Science Fiction #2"),
linking to `/lines/:id` — every number in the line (isfdb-adapter
`/pubseries`, cached a day), each marked Yours / Another edition /
Wanted / Missing, missing ones linking to Add a book. **Collecting a
line** is a `LineWant` record, synced on creation and nightly at 02:30
(`LineWants::Sync`): every number that isn't Mark's printing — including
a book he has in another edition — and isn't excluded becomes a want
hunting that printing (`printing_override_ids`), a book not yet
catalogued being added from its ISFDB title. A want of Mark's own keeps
its covers and gains the printing; wants the line made remember it
(`wants.line_want_id`), so "Stop collecting" removes only those. "Not
this one" sticks (`excluded_pub_ids`). Sync waits for the full line —
never a partial list — so it starts after the mirror re-import that
brings line names.

The publication-series adapter deploy (39814fc) was reverted: the mirror
lacked the `pub_series` table (refresh.py's import allowlist); 6f7182f
adds it and lets the adapter cope until the re-import.

## #catalogue: what changed, on Discord (2026-11-07)

Mark: with nightly jobs now changing the catalogue on their own, a
summary of each change — in its own channel, out of #general's way.
Changes are recorded as they happen as `CatalogueEvent`s — one readable
line each ("Added The Days of Glory: Five Star (UK) 1973, owned", "Kraken
(Pan 2011): owned → sold", "Brasyl: 1 new printing in ISFDB") — rather
than read back from paper_trail, which stores only each record's previous
state. `origin` is "web" for Mark's edits, else the job.
`CatalogueReport` posts Mark's edits every 15 minutes once a burst has
settled, and a 04:30 digest of the jobs' changes: books newly found by a
provider, new printings of books already known (wanted books first,
starred), decisions the sweep closed, the phone app rebuilt. Recorded
where things change: add a book, want/unwant, printing changed, status
and purchase details, edition deleted, readings, review-screen and
metadata-cog decisions; KnownEditionsRefresh, the sweep, the snapshot
job. Posts go to `credentials.discord.catalogue_channel_id` only — never
#general — and wait (recorded, unposted) until it's set.

## Pending decisions stay live (2026-11-02)

Mark: anything that changes an edition outside the review screen can
leave decisions behind that no longer have anything to decide. Rather
than each feature cleaning up its own slice, `PendingDecisionSweep`
holds one rule: a decision about an edition closes when the edition is
gone (rejected), its source's record is gone (rejected), or every field
it disputes now agrees — publisher variants by the authority file, covers
by checksum (accepted, the same close a fresh fetch makes). It runs after
every interface change to an edition (review-screen accept, metadata cog,
"Not this printing?"), on any edition's destroy, and nightly at 3:10 over
the whole queue as a backstop. Measured on the prod copy the day it was
built: 0 of 418 moot (265 fully live, 52 agreeing on some fields), so it
prevents cruft rather than clearing a backlog.

## Settled (2026-11-02)

- **Reviews:** later. Posting to Goodreads was manual, so nothing is lost
  meanwhile.
- **Open Library covers:** cached locally, the same as ISFDB's.
- **Search:** submit-to-search, gentle on Open Library; must match
  editors and alternate titles, and fold punctuation.
- **The book page** becomes catalogue management (its job changes from
  reference, `docs/UI_PRINCIPLES.md` principle 2).
