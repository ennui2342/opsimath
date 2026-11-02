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
dates, rating and review). Acquiring a wishlist book deletes the
`WishlistItem` (today's rule, `docs/INTEGRATIONS.md`) and takes its
bargain-hunting data with it. Buying from a `/finds` listing could
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

## Build order

Each step usable on its own and checked against real data, as for
bargain hunting.

1. **State changes on books already in the catalogue.** The ~2,000
   catalogued works need the reading log and ownership actions now:
   started / finished / DNF (dates, rating, review), acquired / sold /
   given away, and for a wishlist book "acquired" and "remove". No
   providers needed; restores what the Goodreads sync used to do for
   existing books.
2. **Provider layer + Open Library.** A provider registry with
   capabilities (search works, a work's editions, ISBN lookup); ISFDB
   moved behind it; an Open Library client; Open Library editions as
   `EnrichmentRecord`s.
3. **Add a book.** Search → work → edition cards (publisher + cover) →
   intent → step 2 enrichment. Acquiring a wishlist book runs the same
   edition picker, pre-selected from its bargain-hunting printings.
4. **Edition picker for existing books** — change which edition you
   own, and settle the queued printing choices in the same screen.
5. Later: discovery; then federation.

## Open questions

- **Where reviews go.** Opsimath holds reviews as Markdown; the
  scifipraxis pipeline publishes them. Does writing a review in opsimath
  feed that pipeline directly now that Goodreads is out of the loop?
- **Search UX.** Submit-to-search rather than live per keystroke (Open
  Library asks for gentle use); matching editors and alternate titles.
- **Open Library covers** (`covers.openlibrary.org`): use their URLs, or
  download into Active Storage like ISFDB covers?
- **What the book page becomes.** Today it's reference only
  (`docs/UI_PRINCIPLES.md` principle 2); adding actions changes its job.
