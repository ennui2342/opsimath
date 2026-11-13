# Home page

Agreed with Mark 2026-11-13. The page "opsimath" in the header opens —
what he's reading, how the year's going, what to read next, and what he's
been doing. Phone first (he mostly uses opsimath on his phone).

## Order

1. **Currently reading** — each open reading as a compressed edition card
   (Ui::EditionCardComponent `:row`), with how long it's been open and a
   one-tap **Finished**. A read that's dragging (below) says so.
2. **The year** — the reading goal and pace.
3. **Up next** — three recommendations, each with its reason.
4. **Series to finish.**
5. **The river** — Mark's own recent activity.

Nothing about pausing or tidying stale reads: Mark is cleaning up his
currently-reading list himself (Books → Reading).

## The year: goal and pace

- **Goal**: a yearly target, a setting (2026: 78). Counted as completed
  readings with a finish date in the year — rereads count.
- **Status**: "42 of 78 · 23 behind where you'd be by now · 5.1 a week
  to make it" — where he'd be is the goal × the fraction of the year gone;
  the weekly rate is what's left over the weeks left. Ahead of pace, it
  says so instead.
- **Pace now**: books a week over the last 12 weeks, against his pace
  over the last 12 months ("1.2 a week lately · 1.0 a week this past
  year").
- **Pace over the years**: books finished per year as a small bar chart
  (every year with dated finishes; 2024 and 2025 were 53 each).
- **Days per book**: his median days from start to finish, from readings
  with both dates (all-time median 11 days).

## Dragging and slumps

- **Expected time** for an open read: its edition's pages ÷ his pages a
  day (median over completed readings with both dates and a page count);
  without a page count, his 75th-percentile days to finish (23).
- **Dragging**: open more than twice its expected time, or longer than his
  90th percentile (70 days).
- **Slump**: fewer finishes in the last 60 days than his 12-month pace
  predicts.

Either switches Up next into **quick-win mode**.

## Up next: recommendations

From books Mark owns and hasn't finished, **fiction only** (Mark: leave
non-fiction out). Each candidate gets a score from these signals; the
three shown are chosen for *different* reasons, each stated on its card:

- **Author affinity** — his average rating of the author, shrunk towards
  his overall mean by how few of theirs he's rated (a Bayesian average:
  two 5★ reads beat one; one 4★ isn't over-weighted).
- **Series momentum** — the next unread book of a series he's read and
  liked, more so the higher he rated it and the more recently.
- **Echoes of recent loves** — shares an author, series, publisher's line
  or subject with his 4–5★ reads of the last two years.
- **Fresh arrivals** — editions acquired in the last 90 days.
- **Long-shelved** — a gentle boost for books owned for years.
- **Quick win** (only when dragging or in a slump) — strongly favours
  short books (under ~250 pages, novellas) by high-affinity authors, and
  steers away from the dragging book's author and form.

Each card offers **Not now** (hidden 30 days) and **Not for me** (hidden
for good). Which recommendations he goes on to start is recorded, so the
weights can later be tuned from evidence.

Book forms (novel, novella, collection, anthology, non-fiction, omnibus)
come from ISFDB — synced from 2026-11-13; until then nearly everything
said "novel".

## Series to finish

Series where he's finished at least one book but not all of them (by
ISFDB's full volume list where the series is tied to ISFDB), ranked by
how he rated the ones he read and how recently. Each shows its next book:
on his shelf, wanted, or neither (with Want it).

## The river

Mark's own actions only (CatalogueEvent from the web): books added,
editions chosen, readings started and finished, wants. Newest first,
grouped by day.
