# Bargain hunting: eBay listings for wishlist books

Poll eBay UK for active listings of wishlist books, work out **which
printing** each listing is, and surface the ones that are both the
printing Mark actually collects and cheap. Notify via Discord; act on
finds in the web app.

Designed 2026-10-24, after a probe against the real wishlist (below).
**Steps 1 (printings, author status, collecting profile, favourite
artists) and 2 (eBay search + printing identification) built
2026-10-24**; steps 3 (web) and 4 (notifications) not yet.

The key requirement is the *printing*, not just the book (Mark: *"for
older books, I'm basically collecting A-format paperbacks. So I want
something specific rather than modern reprints. I'm not interested in,
say, SF Masterworks and things like that"*). A bargain on the wrong
printing isn't a bargain. Finding listings turned out to be easy;
identifying the printing is the real work.

## Scope

- **Wishlist only.** `to-read` means owned-but-unread in opsimath (the
  Goodreads `to-read` shelf creates a `Copy` — `docs/INTEGRATIONS.md`), so
  it isn't a buying list. Hunting for better copies of owned books is
  possible later, but out of scope here.
- **eBay UK (`EBAY_GB`) active listings**, via the Browse API. Sold
  prices (Marketplace Insights API) are restricted to approved partners,
  so "bargain" has to be judged without them (see *Judging a bargain*).
- **Read-only against eBay.** No bidding, watching or buying through the
  API — opsimath finds and links; Mark buys on eBay.

## What the probe found (2026-10-24, real data)

The wishlist is 339 `WishlistItem`s, all from the Goodreads `wishlist`
shelf. None has a `work_id`, ISFDB id, priority, or notes; 319 carry the
ISBN of the one printing Goodreads happened to pick (often a US mass
market, or a modern reprint).

**ISFDB expansion** (`Isfdb::Client#lookup_editions` on that ISBN — no
`Work` needed): 252/319 resolve, giving 1,728 printing ISBNs in total
(median 6 per book, max 55). It reaches the UK printings — Gollancz,
Pan, Orbit, Gateway — but also ebook/audio ISBNs (Audible, Recorded
Books, Open Road) that must be filtered out by binding. The other 67
aren't in the ISFDB mirror (mostly non-genre or very recent books).
Pre-ISBN printings come back without an ISBN (e.g. the 1976 SF Book Club
edition of *Hello Summer, Goodbye*), so ISBN can't be the only key.

**eBay search** (all 339 books, ~2,400 calls, responses cached):

| Search | Books with a hit |
|---|---|
| Goodreads ISBN alone (`gtin=`) | 116 (34%) |
| Every ISFDB printing ISBN | 213 (63%) |
| Title + author, Books category, junk-filtered | 334 (99%) |
| Any UK-located listing | 312 (92%) |

- **Keyword search finds the listings; ISBN search barely adds to it.**
  Searching every ISBN found a UK listing keyword search missed for
  exactly **one** book. Its apparent 406 "extra" UK listings were almost
  all on popular titles where keyword search hit its 50-result page cap —
  fixed by restricting to UK sellers and sorting cheapest-first, not by
  2,000 extra calls a day.
- **Many sellers don't attach an ISBN**, which is why `gtin=` misses so
  much. It also means the printing has to be inferred from listing text
  and item specifics, not just looked up.
- **27 books have no UK listing at all** — mostly obscure older books
  listed only by US sellers (*Psykosis*, *The Eden Cycle*,
  *Communipaths*). Two (*Fellahin*, *Gráinne*) have no listings anywhere.
- Junk-filtered keyword matches were checked by eye for 20 books: real
  copies of the right books. Not checked for all 339.

The probe script and cached responses are throwaway (scratchpad), not
part of the build.

## Pipeline

```
WishlistItem ──ISFDB expansion──▶ WishlistPrinting (cached, weekly)
     │                                   │ wanted? (collecting profile + override)
     ▼                                   ▼
 eBay search (daily, 1–2 calls/book) ─▶ EbayListing ─▶ identify printing
                                                          │
                                       bargain? ◀─────────┘
                                          │
                       Discord digest · web "Finds" queue · tm task (strong finds)
```

### 1. Expansion: `WishlistPrinting`

The ISFDB printings of each wishlist book, cached per wishlist item.
Same shape and refresh policy as `WorkSiblingIsbns` (weekly, re-query
when the source ISBN changes, a wall-clock deadline). Unlike that cache,
it keeps each printing's details, because the rest of the pipeline
reasons about them:

```
WishlistPrinting
  wishlist_item_id   fk
  isfdb_pub_id       unique per wishlist item
  isbn13, isbn10     nullable (pre-ISBN printings)
  publisher          resolved through Authority (publisher vocabulary)
  binding            ISFDB code: pb / tp / hc / ebook / audio / digest / …
  publish_date       EDTF string, as Edition.publish_date
  cover_artist, cover_url
```

No `wanted` column: whether a printing is wanted is decided on read by
`CollectingProfile#verdict`, so changing the profile or an override
takes effect at once with nothing to recompute.

Physical bindings only. `ebook`/audio rows are dropped at refresh time,
not stored. Publisher names are resolved through the existing authority
file, so `Pan Books` / `Pan` / `Pan Macmillan` compare as one publisher
when matching a listing.

The 87 items with no ISFDB match (67 unresolved ISBNs + 20 without one)
get no printings. They're hunted as "any physical copy" and every find
is shown as *printing unknown*.

### 2. What counts as wanted: the collecting profile

Mark collects paperbacks for their **cover art and artists**, in a
format, not for being early printings (*"I'm looking really for
interesting cover art from artists that I like, and in a format… in
some cases later editions are more desirable"*). And he buys recent
books by living authors **new**, to pay the author. So the rule is
format first, then cover, and some books aren't hunted at all
(`CollectingProfile#verdict`, agreed 2026-10-24):

| Book | Rule | Wanted |
|---|---|---|
| Has an A-format printing (ISFDB `pb`) | `a_format` | every A-format, any year |
| No A-format; recent (first published in the last `recent_years`, default 5) **or** author alive | `buy_new` | nothing — not hunted |
| No A-format; older **and** author dead | `b_format` | B-formats (ISFDB `tp`) |
| …and never paperbacked at all | `no_paperback` | any physical printing |
| ISFDB has no printings; author dead | `unknown_printings` | hunted, every listing's printing unknown |
| ISFDB has no printings; author alive or unknown | `buy_new` | nothing |
| `printing_override_ids` set | `override` | exactly those printings |

- **Book club editions are never wanted** and don't count as an
  A-format (`WishlistPrinting::BOOK_CLUB`: "Book Club", SFBC, BCA,
  `/ BCE`, Readers Union…).
- **Any country.** US mass-market paperbacks are A-format too.
- **`buy_new_override`** forces buy-new on or off for one book.
- **B-format can't be told from C-format.** ISFDB's `tp` covers both
  (B ≈ 198×129mm, C ≈ 234×153mm). Some C-formats will turn up; judge
  from the listing.
- **No condition filter.** "Acceptable" copies are fine; only "For parts
  or not working" is dropped.
- **Cover choice comes next.** Within the wanted formats, Mark picks the
  covers he likes per book (*Front end*); printings sharing a cover are
  one choice and one price group.

**Author living or dead** comes from ISFDB's author record
(`Isfdb::WishlistAuthorRefresh`, monthly per item). The author is found
by searching the surname, then the full name, and comparing full names
with case and punctuation folded ("J.G. Ballard" = "J. G. Ballard").
Several matching records are variant spellings of one person ("Ursula
K. Le Guin" #37 / "Ursula K. LeGuin" #229311); the oldest is the main
record. An author that can't be identified counts as living, so the
default leans towards paying the author. On real data: 216 living, 100
dead, 23 unknown — nearly all non-genre authors ISFDB doesn't hold, plus
names with accents the adapter can't search (Lem). ISFDB has no dates at
all for some authors (Ray Faraday Nelson, d. 2022; Ryu Mitsuse, d. 1999),
so they count as living; `buy_new_override` fixes a book where that
matters.

**Favourite artists** are worked out from the collection each time:
artists on at least `favourite_artist_min_owned` (default 5) owned
editions, plus `favourite_artists_always`, minus
`favourite_artists_never`. Nothing to maintain as books are catalogued —
ISFDB enrichment fills in `Edition.cover_artist` and the counts move —
only the two exception lists. They flag a find, they don't filter: a
listing whose cover is by a favourite is notified at once, others go to
the digest and the Finds page. 31 artists at the default threshold
(Chris Moore 45, Jim Burns 32, Bruce Pennington 19, Peter Jones 18, Fred
Gambino 18, Michael Whelan 16…); 172 of the wishlist's A-format
printings have a favourite's cover.

### 3. Search

Daily, per wishlist item:

1. **Keyword search** — `q = "<short title> <author>"`, Books category
   (`267`), `filter=itemLocationCountry:GB`, `sort=price`, limit 50.
   Cheapest-first matters: it means the 50-result cap drops the
   expensive listings, never the bargains.
2. **Goodreads-ISBN `gtin=` search** — one extra call as a cross-check.
   Not every sibling ISBN; the probe showed that costs ~2,000 calls a
   day for one extra book.

Weekly, a **worldwide** keyword search (no country filter) for items
with no UK hit, for the 27 books only US sellers carry. Postage is
included in the price for these, since it can dominate.

Junk filter (keep the probe's, then tune on real data): drop job lots,
bundles and "set of"; require the author's surname and the title's first
words in the listing title.

### 4. Identify the printing

The listing's **photo** is the main evidence, not its ISBN. Older
printings often share one ISBN across reprints with different cover art,
and eBay sellers attach a catalogue ISBN whatever copy they actually
have. The photo shows the copy being sold. (Mark's suggestion: reuse the
cover-compare sidecar already used for Goodreads-vs-ISFDB covers. Spike
results below.)

Evidence in order, each step narrowing what the previous left open:

1. **Cover match.** Compare the listing's main photo (in the search
   results already, so no API call) against the ISFDB cover of every
   physical printing of the book, using `Enrichment::CoverCompareClient`.
   - One printing clearly above the rest → that printing.
   - Several printings tied (they share cover art) → narrowed to that
     group; steps 2–3 may split it. If every printing in the group is
     wanted, or none is, the answer doesn't matter and identification
     stops.
   - Nothing scores as the same cover → on to steps 2–3 with all
     printings still possible.
2. **Text signals** in the listing title: ISBN, publisher (via authority
   variants), year, "paperback" / "hardback" / "1st". Narrows to a
   printing if exactly one in the remaining set fits. An ISBN only
   narrows to *the printings sharing it*. It never overrides a confident
   cover match: when they disagree, the photo wins and the listing is
   marked for an eyeball check.
3. **Item specifics** via `getItem` (`localizedAspects`: ISBN, Publisher,
   Publication Year, Format). Costs a call per listing, so only for
   listings still unresolved after 1–2 that survive the price check,
   newest first.
4. **Unresolved** → *printing unknown*. Not notified unless the item has
   no printings at all; shown in the web app for an eyeball check.

Each `EbayListing` records how it was identified (`cover` / `text` /
`aspects` / `unknown`) and keeps the cover-match scores. That shows how
well identification is working and which listings deserve a look.

**Thresholds.** `CoverApplier`'s own thresholds (`ratio >= 0.2`,
`inliers >= 350`) were set for comparing two clean cover images. Phone
photos of a real copy score lower, so this needs its own, looser pair.
The spike used `0.08` / `30`; confirm against Mark's eyeball checks in
build step 2.

#### Cover-match spike (2026-10-24)

Main photos of 138 eBay listings for 60 wishlist books (older books
first), each compared against the ISFDB covers of all physical printings
of its book. Ground truth was the ISBN the seller attached, counting
*every* printing sharing that ISBN as correct.

| Outcome (ratio ≥ 0.08, inliers ≥ 30) | Listings |
|---|---|
| Matched a printing with the declared ISBN | 90 (65%) |
| Tie across declared + other printings (shared cover art) | 16 (12%) |
| No confident match → would be *printing unknown* | 29 (21%) |
| Confident match to a different printing | 3 (2%) |

With `CoverApplier`'s stricter thresholds, *unknown* rises to 58 and
correct falls to 70; conflicts stay at 3. So the looser pair costs no
accuracy here.

- **The 3 conflicts are mostly the seller's ISBN being wrong, not the
  photo match.** *Gravity's Rainbow* listed as "Revised Edition 1991"
  matched the 1991 Viking but carried the 1973 ISBN.
- **ISBN reuse is real and the photo resolves it.** *The Birthgrave*:
  Orbit's 1977, 1979 and 1985 printings share ISBN 0860079422; the
  seller's own photo (a real copy on a sofa, not a stock image) matched
  the 1979/1985 art, which is completely different from 1977's. The
  listing title said 1985.
- **Shared art can't be split by photo** — same-cover reprints, and
  ISFDB reusing one scan for several printings. Usually harmless for the
  wanted rule, since same-art printings tend to be the same era.
- **Bias:** listings with an attached ISBN skew towards booksellers, some
  of whom use stock catalogue images (21 of the 150 scored ≥ 0.5, which
  suggests a scan or stock image rather than a photo). Real
  used-book photos are what matter. The Birthgrave case shows they work,
  but the 21% unknown rate is likely higher on private sellers' photos.
- 8% of ISFDB printings have no cover image; those can only be
  identified by steps 2–3.

### 5. Judging a bargain

**Prices are compared per printing, never per book.** A first-printing
A-format and a modern reprint of the same novel are different markets:
the reprint is usually the cheapest copy on eBay, and comparing a wanted
printing against it would hide every real bargain and flag false ones.
(Mark: *"the price that we want to track is going to be highly dependent
on the edition… look at editions' pricing independently… rather than
just looking at the cheapest one."*) This is the main reason
identification matters so much.

The unit of comparison is the **price group**: the set of printings a
listing was identified as. Usually one printing; a shared-art tie
(step 4.1) is one group, since photos can't separate them and their
prices are typically the same anyway. Listings with *printing unknown*
never enter a price group, so they can't distort its baseline.

No sold-price data, so three signals, any of which can flag a listing
on a wanted printing:

- **Target price** — optional per wishlist item (`target_price`, pence).
  Anything at or under it is a find.
- **Spread** — price + UK postage well below the median of current
  listings *in the same price group*. Needs a minimum number of
  listings in the group to mean anything; below that, this signal is
  skipped rather than computed from two copies.
- **History** — below what opsimath has itself seen listings in that
  price group go up at. `EbayListing` rows are kept after a listing
  ends, so they build per-printing history from polling with no extra
  table. Weak at first; improves with time.

The `/wishlist/:id` screen shows prices broken down by printing — the
current range and the history for each — so it's visible what a wanted
printing typically costs before setting a target price.

Thresholds are deliberately not fixed here; set them after a few weeks
of real listings, as the probe did for search.

### 6. Report

- **Discord**: a daily digest of new finds via `DiscordNotifier`, one
  line each with title, printing, price + postage and a link. Separately,
  an immediate message for a wanted-printing **auction ending within 24
  hours** under target.
- **tm task**: only for strong finds (under target price, wanted
  printing identified by ISBN or aspects), so the queue isn't noise.
- **Web app**: everything, including what Discord deliberately leaves out.

Each listing is notified once (`EbayListing.notified_at`). A price drop
on a known listing re-notifies only if it newly crosses the target.

### 7. Auctions ending soon

A frequent pass (hourly) re-reads only known, unended auction listings
on wanted printings that end within 24 hours. That's one `getItem` each,
a handful of calls, giving current price and bid count close to the end.
Discovery stays daily.

## Data model additions

```
WishlistItem  (+)
  target_price            integer pence, nullable
  printing_override_ids   bigint[] of isfdb_pub_id, nullable (null = use profile)
  printings_refreshed_at
  buy_new_override        boolean, nullable (null = the profile decides)
  author_isfdb_id         nullable — null after a check = author unknown
  author_died_date        EDTF, nullable — null with an id = living
  author_checked_at

WishlistPrinting          (above)

CollectingProfile         single row
  recent_years                 5
  favourite_artist_min_owned   5
  favourite_artists_always     string[]
  favourite_artists_never      string[]

EbayListing
  wishlist_item_id        fk, dependent: :destroy; unique with ebay_item_id
  ebay_item_id
  title, url, image_url
  price                   pence, GBP (eBay converts); the Buy It Now price
  current_bid             pence; auctions
  shipping, shipping_type pence (null = unknown/collection); FIXED / CALCULATED
  original_currency       when eBay converted
  condition, buying_options[], auction_ends_at, bid_count, seller_country
  found_by                keyword / gtin
  matched_pub_ids         bigint[] isfdb_pub_ids — one printing, or a shared-cover group
  identified_by           cover / text / unknown; null = not tried yet
  cover_scores            jsonb {isfdb_pub_id => {ratio, inliers}} — kept for tuning
  first_seen_at, last_seen_at, ended_at, notified_at
  status                  new / dismissed / bought
```

The collecting profile is editable under `/settings` like the authority
files (step 3); the favourite-artists page shows the computed list with
owned counts beside the two exception lists.

When a wishlist item is fulfilled and deleted (the Goodreads
wishlist → to-read move), its printings and listings go with it —
`ShelfSync` removes it with `destroy_all`, so `dependent: :destroy`
applies (covered by a ShelfSync test; a bare `delete` would instead fail
the sync on the foreign keys). Nothing else to clean up: the sweep only
searches current wishlist items, so a bought book is never searched
again.

`goodreads:rebuild` truncates every book table, which takes the price
history with it (it hangs off wishlist item ids the rebuild recreates).
The collecting profile is kept, as configuration.

## API budget

Browse API default quota: 5,000 calls/day.

| Pass | Calls |
|---|---|
| Daily keyword + Goodreads-ISBN search, 339 books | ~680 |
| `getItem` for new, unidentified, price-plausible listings | tens/day steady state; the first sweep's backlog is drained over a few days, newest first |
| Hourly ending-soon auction checks | a handful per run |
| Weekly worldwide search for books with no UK hit | ~30 |

Comfortably under quota, with room for the wishlist to grow. Cover
matching costs no API calls (the photo URL is in the search results),
only cover-compare sidecar time: one comparison per physical printing
per *new* listing. The first sweep's backlog (thousands of listings ×
~6 printings) is drained over days like the `getItem` backlog; after
that it's tens of new listings a day. If it gets
tight, switch the `gtin=` cross-check to weekly first.

Credentials go in Rails credentials (`ebay.client_id`,
`ebay.client_secret`), like Goodreads and Discord, so no cluster change
is needed. The OAuth token (client credentials, ~2h lifetime) is cached
in `Rails.cache`.

## Front end

There is no wishlist screen in the web app today — the wishlist exists
only on Goodreads and in the mobile PWA's snapshot. Discord alone was
the original plan, but the printing requirement changes that: choosing
which printings you want, and dismissing a listing that's the wrong one,
both need somewhere to happen.

### Phone first, but not inside the offline PWA

Mark rarely visits the web app, and finds arrive on his phone via
Discord anyway, so the screens that act on finds must work well on a
phone. That doesn't make the shop-lookup PWA the right home for them:

- **Finds are live; the PWA is a daily snapshot.** The snapshot is
  rebuilt once a day and downloaded on wifi (`docs/MOBILE.md`). An
  auction ending this afternoon or a listing sold an hour ago would show
  stale there.
- **Finds need writes; the PWA has none by design.** Dismiss, wrong
  printing and bought all write back. `docs/MOBILE.md` keeps the PWA
  strictly read-only so it never needs offline-sync machinery
  (`PHILOSOPHY.md` principle 15), and lines up Turbo Native for any
  interactive mobile client.
- **A second implementation of each screen.** The PWA is hand-written JS
  (`pocket.js`) beside the server-rendered web app. The edition card
  already has to be kept in step across both (`Ui::EditionCardComponent`
  and its `pocket.js` twin); every finds screen would add another pair.

So the finds screens are **phone-first pages in the web app**: designed
for a phone screen, used from a desktop too, and reached by tapping the
link in the Discord message. The installed PWA gets a "Finds (n)" link
that opens them; they need a connection, which acting on an eBay listing
needs anyway. If a native shell is built later (Turbo Native), these
pages drop straight into it.

The shop-lookup PWA does get one bargain-hunting addition, shown under
*Mobile PWA* below.

Three screens, all built from existing patterns (`docs/DESIGN_SYSTEM.md`):

### `/finds` — the action queue

The *Queue / index list* pattern, like `/pending_decisions`, with the
*"All caught up"* empty state. One row per notified-or-flagged listing:
the eBay photo next to the cover of the wanted printing, title, printing
badge (with how it was identified), price + postage, "ends in" for
auctions, why it's a find (under target / below median / below seen).

Actions, with keyboard shortcuts like the decision screens:
- **Open on eBay** (`o`)
- **Dismiss** (`d`) — not interested in this listing
- **Wrong printing** (`w`) — opens a picker to re-assign it to the right
  printing, or to *not this book*. This feedback is also how the
  identification rules get tuned.
- **Bought** (`b`) — marks the listing; the catalogue update still comes
  from moving the book to `to-read` on Goodreads, as today.

The Discord links point here, not straight to eBay, so the next action
can be taken in one place.

### `/wishlist` — the wishlist itself

A list of wishlist items: cover, title/author, a summary of the wanted
printings ("Pan pb 1978 · 1 of 6 printings wanted"), the cheapest live
wanted-printing listing, and the count of live listings. Sort by best
find, by price or by title.

### `/wishlist/:id` — printings and listings for one book

- **Printing picker** — the ISFDB printings, rendered with the shared
  edition-card layout (`Ui::EditionCardComponent`), each with a wanted
  toggle. The default comes from the collecting profile; changing any
  toggle sets the item's override.
- **Target price** field.
- **Live listings**, grouped by printing, with each printing's price
  range and history; the unknown-printing ones last for an eyeball
  check.

The printing picker is the least phone-shaped of the three: a desk task,
done once per book. It still has to work on a phone, but it's the one
screen where a desktop is the expected place to use it.

### Mobile PWA: shop price check

This is the one bargain-hunting feature that does belong in the offline
PWA, because it answers a shop question. The snapshot already holds
every wishlist item. Adding "wanted printing on eBay from £x" to a
wishlist entry shows, when holding a copy in a shop, whether the shop's
price is good. A day-old price is fine for that, so the one-way snapshot
fits. Cheap to add once `EbayListing` exists.

## Step 1 on real data (2026-10-24)

`bin/rails bargains:printings` (★ = favourite artist; `TITLE=`,
`RULE=`, `SUMMARY=1`), run against a mirror of production: 1,797
physical printings for the 339 wishlist books.

| Rule | Books |
|---|---|
| `a_format` | 145 |
| `buy_new` | 164 — 53 recent, 45 older by living authors, 66 not in ISFDB |
| `unknown_printings` (hunted, dead author) | 21 |
| `b_format` | 8 |
| `no_paperback` | 1 |

- The B-format books are what the rule intends: older books by dead
  authors never in A-format — Priest's *The Adjacent*, Aldiss's *Harm*,
  Goonan's *In War Times*, C. L. Moore's *Black Gods and Scarlet
  Dreams*.
- A first version wanted only "original-era" paperbacks (within N
  years of first publication). Mark rejected it: early covers are often
  poor and the peak artists came later, so the window was dropped.
- **ISFDB misses.** 87 items get no printings — mostly ISBNs the mirror
  doesn't hold, including real SF (*Emphyrio*). A title + author
  fallback (isfdb-adapter `/search`) would recover many; not built.
  Retitled US editions are likely missed the same way (*Hello Summer,
  Goodbye* was *Rax* in the US).
- **Undated printings**: 238 of 1,797. No longer matters for the rule,
  which has no date window; only "recent" uses a date, and it uses the
  book's earliest dated printing.

## Step 2 on real data (2026-10-24)

`bin/rails bargains:sweep` (search, then identify a batch),
`bargains:identify LIMIT=`, `bargains:finds` (per book, live listings
grouped by identified printing; ✓ wanted, ★ favourite artist). Run
against a production mirror with the real Browse API:

- **Sweep:** 175 hunted books, 343 API calls, under 4 minutes. 2,449
  relevant UK listings across 160 books (2,389 by keyword, 60 more only
  by the wishlisted ISBN).
- **Identification:** ~1.1 s per listing (one cover-compare call per
  distinct ISFDB cover). First 300, cheapest first: 179 by cover (60%),
  20 by title text (7%), 101 unknown (34%). Scheduled nightly at 1,000
  a run, so a first sweep's backlog clears in about three nights;
  after that it's the day's new listings.
- **Cross-check:** of 28 cover-identified listings whose title quotes a
  year, 20 matched a printing of that year. The other 8 are mostly the
  right cover from a neighbouring printing with the same art (a 1971
  Penguin matched to the 1946 Penguin; Grafton reprints to the 1986
  Grafton; undated ISFDB printings) — benign when collecting by cover.
  One looks wrong: a 2014 Sphere *Books of Blood* matched to the 1988
  Warner at ratio 0.085, just over the threshold. Watch for more before
  raising it.
- **Cheapest-first means bulk sellers first** ("…, Used; Very Good
  Book"). Their photos are stock catalogue images, which match ISFDB's
  scan very strongly (0.4–0.8) — identifying the catalogue edition they
  listed against, which is usually but not always the copy they ship.
- **Shared art across formats.** When an A-format and a B-format used
  the same cover (*Brasyl*: Gollancz `pb` 2008 and `tp`), the photo
  can't separate them; the group then counts as wanted if any printing
  in it is.
- **Wrong books** that pass the title/author check — study guides (York
  Notes, "Study Texts") for classics — are now filtered as junk. Others
  (*Nightfall Two*, a different Asimov collection) end up *printing
  unknown*, which is never notified.
- ISFDB sometimes stores two cover URLs as `url|url`; the first is used.
- Not built yet from the search design: the weekly worldwide search for
  books with no UK listing, and `getItem` item specifics for listings
  the cover and title can't identify.

## Build order

1. **Printings**: `WishlistPrinting` + refresh job, collecting profile,
   `target_price` / override columns. Rake task to print each item's
   wanted printings — check the profile against real books before going
   further.
2. **Search + identify**: `Ebay::Client`, daily sweep job,
   `EbayListing`, identification steps 1–3. Rake report of
   finds and identification breakdown; no notifications yet. Cover
   matching against the cover-compare sidecar is part of this step.
3. **Web**: `/wishlist`, `/wishlist/:id` (printing picker), `/finds` —
   phone-first, checked on a real phone; "Finds (n)" link in the PWA.
   Then the PWA shop price check.
4. **Notify**: Discord digest, ending-soon auction pass, tm tasks for
   strong finds. Bargain thresholds set from the history gathered by
   then.

Each step is usable on its own and checked against real data before the
next.

## Open questions

- **Batch item lookup** — `getItems` (up to 20 listings per call) would
  cut the `getItem` cost; check it's available to a standard keyset
  before relying on it.
