# Reading lists

Mark chooses books by lists as much as by author or series: award
shortlists (lately the Arthur C. Clarke Award and the Ursula K. Le Guin
Prize; the Hugo and Nebula too) and the canon lists he is working
through, Pringle's *Science Fiction: The 100 Best Novels* (1985) and
Broderick & Di Filippo's *Science Fiction: The 101 Best Novels 1985–2010*
(2012). A list works like a series (docs/CATALOG.md, "Series pages"): a
page with every book on it and where each stands for him, "Want it" on
any he hasn't got, and collecting the list.

Agreed with Mark 2026-11-13.

## Two kinds of list

- **Award lists** — one category of one award ("Arthur C. Clarke Award:
  Best Novel"), every year's winner and shortlist, from ISFDB's award
  data (isfdb-adapter `/awards`, `/awards/categories/:id`; the mirror
  loads ISFDB's award tables from 2026-11-13). Each entry is ISFDB-linked
  to its title. Refreshed nightly, so a new year's shortlist appears on
  its own.
- **Curated lists** — a fixed published list ISFDB doesn't record:
  Pringle 100, Broderick 101, kept as data files (`config/book_lists/`,
  each citing its source). Each entry is matched to its ISFDB title on
  import (title and author surname); one that doesn't match shows on the
  page as unmatched, with an "Add" link, and is never collected blindly.

One model for both: `BookList` (a name, a short label for badges, the
award category if any) and its `BookListEntry` rows (year, position,
status — winner, shortlisted or listed — title and author as listed, and
the ISFDB title id).

## A list's page

- Every book on it as the standard cards (DESIGN_SYSTEM.md): an edition
  in the catalogue as the compressed edition card, a book not in it as
  the not-in-catalogue card with **Want it** / **Add**.
- Progress at the top: "read 41 of 100 · own 63".
- Award lists grouped by year, winner first; filters **Winners** /
  **Shortlists** and a from-year.
- Lists page (`/lists`, in the header): every list with its progress, and
  adding an award list by picking an award and a category.

## Collecting a list

Like collecting a series: every book on it Mark doesn't have becomes a
want, and bargain hunting takes over. Mark sometimes reads whole
shortlists, not just winners, so collecting takes a **scope** —
*winners* or *the whole shortlist* — and an optional **from year**.
Collecting carries on: each new year's entries in scope become wants as
they appear. "Not this one" excludes a book for good; stopping removes
the wants the list made.

## Elsewhere

- **Book page badges** from the lists Mark has: "Clarke Award winner
  2019", "Clarke shortlist 2024", "Pringle 100 #34".
- **Home page** "Up next" can recommend from a list ("On the 2024 Clarke
  shortlist — you've read 4 of 6") — a later step.

## Build steps

1. isfdb-adapter + mirror: award tables, `/awards`, `/awards/categories/:id`,
   `/titles` `main.awards`. *(filed 2026-11-13)*
2. BookList / BookListEntry, curated imports, award imports, the list
   pages, Lists in the header.
3. Collecting (BookListWant, nightly with the line and series wants).
4. Book page badges.
5. Home page recommendations from lists.
