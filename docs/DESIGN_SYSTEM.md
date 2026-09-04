# Design system

`UI_PRINCIPLES.md` is the *why* — the reasoning a new screen gets checked
against. This document is the *what*: the concrete tokens, components, and
screen skeletons that reasoning has produced so far, written down so the
next screen copies the established pattern instead of inventing a parallel
one. It grows as screens are built — an entry lands here when a second
screen would otherwise duplicate the first, not speculatively.

If you're about to build a screen, read the [checklist](#checklist) at the
bottom first.

## Tokens

Defined in `app/assets/tailwind/application.css` (`@theme`), per principle 6
— named semantic vocabulary, not raw shades repeated across views. Only what
is actually used today; add a token when a second view needs the same
non-default colour, not before.

| Token | Use |
|---|---|
| `conflict-100 / 200 / 800 / 900` | Anything that raised a review: a `PendingDecision` badge, the flagged card in a comparison, a selected radio card, the "needs your call" accent. `100`/`900` are the light/dark fills, `800`/`200` the light/dark ink and borders. |

Everything else is stock Tailwind greys + `green-600` / `amber-600` for
button roles (below). No other custom palette.

### Spacing rhythm

The review screens settled on a consistent vertical rhythm — match it:

- Page wrapper: `w-full max-w-5xl` for a comparison screen, `max-w-3xl` for
  a queue/index list.
- Badge row → `mb-4`. `<h1>` (`text-2xl font-bold`) → immediately followed
  by a `text-sm text-gray-500 dark:text-gray-400` subtitle → `mb-4`.
- The comparison grid → `mb-6`.
- Primary action sits directly under the form; the secondary row is
  `mt-3 flex gap-3` with a "Back to queue" link pushed right by `ml-auto`.

## Components

`app/components/ui/`. Every `Ui::` component has a preview
(`test/components/previews/ui/`, browsable at `/rails/view_components`) and a
unit test — principle 5. Reach for one of these before writing a bare
`<span>`/`<div>` that duplicates it.

### `Ui::BadgeComponent`

A small labelled pill. `text:` + `variant:` (`:default` grey, `:conflict`
amber, `:success` green, `:info` blue, `:accent` purple — the last two
added 2026-09-04 so a reading-status fact never collides in color with an
ownership one: `:info` "Read" reads distinctly from `:success` "Owned"
now, and `:accent` "Reading" from `:default`'s neutral DNF/TBR).
Genre/subject/tag chips on the book page;
kind/shelf/status markers on the review queues. Stack multiple in a
`flex flex-wrap gap-2` row (e.g. a `:conflict` "edition reconciliation" next
to a `:default` shelf name).

### `Ui::ComparisonCardComponent`

One card in a **comparison-review** layout. Dumb renderer — the model method
that builds the cards owns all the "which fields, which are selectable"
logic (`PendingDecision#comparison_cards` / `#printing_choice_cards` /
`#edition_reconciliation_cards`). All feed it the same
`Ui::ComparisonCardComponent::Card` / `::FieldRow` structs.

`Card` knobs:

| knob | effect |
|---|---|
| `label` | uppercase card header |
| `meta` | date shown top-right of the header (anything `to_date`-able) |
| `proposed` | flags the card that raised the decision — conflict ring + tinted header |
| `cover` | an ActiveStorage attachment to show |
| `cover_url` | a remote image URL to show instead (incoming feed rows have no attachment) |
| `cover_chip` | provenance badge under the cover (which provider it came from) — a `FieldRow`'s `chip`, for the cover; only shown when `cover` is attached |
| `cover_selectable` | render the "Apply this cover" checkbox over the cover |
| `show_empty_cover` | draw the dashed "No cover" placeholder when nothing is attached |
| `fields` | `FieldRow`s; a `selectable` one gets a pre-checked `fields[]` checkbox and the conflict highlight |
| `identifiers` | `[[label, value], …]` mono footer |
| `info_note` | small muted line at the card foot ("Reference only …") |
| `select_name` / `select_value` / `selected` | turns the whole card header into a radio — picks this card among its siblings; a checked card takes the same conflict ring as `proposed` (pure CSS, `has-[:checked]:`) |
| `input_scope` | id prefix for this card's checkboxes/radio, so N cards with the same field names don't collide (`"pub35244_"`) |
| `fields_disabled` | render this card's checkboxes unchecked + disabled — a printing-choice card whose radio isn't the picked one; a Stimulus controller flips it as the radio changes |

Three selection idioms:

- **Per-field checkboxes** (`FieldRow#selectable`) — "which of these values
  do I want", `enrichment_conflict`. Submits `fields[]`.
- **Whole-card radio** (`select_name`) — "which of these candidates is it",
  the `edition_reconciliation` kind. Submits one value under `select_name`.
- **Both, combined** — "which printing, *and* which of its fields":
  `enrichment_printing_choice` (`PendingDecision#printing_choice_cards`).
  Each candidate card has a header radio *and* per-field checkboxes;
  `input_scope` keeps the ids distinct, `fields_disabled` +
  `printing_choice_controller.js` keep only the picked card's checkboxes
  live so the form never submits fields from a printing you didn't
  choose.
- **Checkboxes, mixed freely across N cards** — "which *source*, per
  field": the edition-metadata screen (below). `field_value_prefix` makes
  every checkbox in a card self-describing (`field_picks[]` =
  `"<provider>:<field>"` instead of `fields[]` = `"<field>"`), and
  `field_pick_controller.js` keeps at most one source ticked per field —
  checking "publisher" on the ISFDB card unchecks it on the Goodreads
  card. `fields_start_checked: false` starts every box unticked (unlike
  the other idioms, nothing here is "the" proposal to trust by default).

### `Ui::EditionCardComponent`

One edition (a printing), laid out the same way everywhere it appears —
`app/components/ui/edition_card_component.rb`, `initialize(edition:)`. The
shape:

```
┌────────┬─────────────────────────────────┐
│ [cover]│  Grafton · 1988 · 471 pages ← bold │  headline: publisher · year · pages
│  h-32  │                                  │   (falls back to format_line if blank)
│  or a  │  [Owned]  [Read]                 │   lozenges: ownership, then reading status
│ dashed │                                  │
│  "No   │  Mass market · Bruce Pennington │   detail_line, muted: format · cover artist
│ cover" │                                  │
│        │  ISBN-13 9780…  ISBN-10 0586…    │   row 1 — ISBNs, plain
│        │  ISFDB 12345↗  Goodreads 1343↗   │   row 2 — linkable ids
└────────┴─────────────────────────────────┘
```

- Cover keeps the page's existing size (`h-32` on the web work page); a
  missing cover gets the same dashed **"No cover"** placeholder
  `ComparisonCardComponent` uses, so a grid of edition cards aligns.
- **`headline`** (bold, top line) is what most distinguishes one printing
  from another — `publisher · year · pages`. **2026-09-04: promoted above
  the format line** (Mark's call — format is secondary once you're
  comparing your own printings against each other). Falls back to
  `format_line` when there's nothing else yet, so the headline is never
  blank.
- **Lozenge row**, `status_badges` — up to two, independent of each
  other: `ownership_badge` (`Owned` `:success` for an edition with an
  owned `Copy`, else the retired disposition `:default` from
  `Copy::DISPOSITION_LABELS`, nil for a catalogue-only edition) and
  `reading_badge` (`Reading` `:accent` for an open or paused `Reading`,
  else `Read` `:info` for any completed one, else `DNF` `:default`, else
  `TBR` `:default` — nil only when the edition has *neither* a copy nor a
  reading, so a bare
  never-owned alternate doesn't claim a false "TBR" intent).
- **`detail_line`** (muted, was the old top line) — `format_line` (as
  before: `format_detail` → `format` → `"Edition"`) plus the ISFDB cover
  artist when known (`Edition#cover_artist`, joined `"First, Second"` for
  multiple credits) — `"Mass market · Bruce Pennington"`.
- The identifier footer is **two mono rows** — ISBNs on the first, the
  linkable ids (`ISFDB`, `Goodreads`) on the second — so it wraps
  predictably instead of interleaving. Order and labels come from
  `EditionIdentifier::DISPLAY_ORDER` / `#label`; a link appears only when
  `EditionIdentifier#external_url` is non-nil — ISBNs are deliberately
  unlinked (no single right destination).

**This layout is shared with the pocket app** (`docs/MOBILE.md`), which
can't use a ViewComponent — it builds cards in plain JS
(`pocket.js` `editionCardHtml` / `idFooter`) against CSS classes in
`pocket.css` (`.edition`, `.edition .headline`, `.edition .ids`). Brought
in step for the 2026-09-04 reorg (headline promotion, reading-status
lozenges, cover artist) the same day — `pocket.js`'s `READING` map mirrors
the web's `reading_badge` precedence (reading/paused > completed > dnf >
default tbr; `Mobile::ShopView#reading_status_of` computes it server-side
since sql.js has no Reading table to query from), and, since a follow-up
pass the same day, its `["info", "READ"]` / `["accent", "READING"]` pairs
use the exact same variant names as `Ui::BadgeComponent` — `.pill.info` /
`.pill.accent` in `pocket.css` are genuinely new colors (blue/purple),
not aliases of an existing token, matching the web fix below. Order and
ISFDB/Goodreads-only linking stay in sync already: `pocket.js`'s `ID_URL`
map mirrors `EditionIdentifier::EXTERNAL_URL_BY_TYPE` and its
`DISPOSITION` map mirrors `Copy::DISPOSITION_LABELS`. The snapshot
carries per edition: `format`, `format_detail`, `publisher`, `year`,
`page_count`, `disposition`, `cover_artist`, `reading_status`,
`isbn10/isbn13/isfdb/goodreads` (`Mobile::SnapshotBuilder` `editions`
table).

A pure wishlist entry (no editions at all) gets the identical card shape
too, as of the same follow-up pass — `pocket.js`'s `wishlistCardHtml`,
same size/left-aligned image as an edition's, no side indent on either
anymore. It just has nothing to headline with (no publisher/year/pages
for something you don't own yet), so the WISHLIST lozenge sits where the
headline line would be, right-aligned rather than stacked below an empty
one — and the ids footer now shows too (`entries.isbn10`/`isbn13`, always
in the snapshot schema but not actually selected by `pocket.js`'s
queries until this pass). A work that's *also* wishlisted (you own one
printing but still want another) keeps the small inline WISHLIST lozenge
next to its title instead — it already has real edition cards below, so a
whole second pseudo-card would be noise.

When you change the edition layout, change it in both places (or write
down why they diverge) — same rule as `feedback_goodreads_path_parity`
for the sync paths.

#### Reconcile this edition — the corner cog

Every edition card carries a small **cog** in its bottom-right corner
(`text-gray-300 hover:text-gray-600`, `absolute bottom-2 right-2`, inline
SVG, `h-4 w-4`, `aria-label`) — the first icon-only affordance in the
app; reuse this exact treatment for the next one rather than inventing a
size/color/position from scratch. It links to
`EditionMetadataController#show` (`/editions/:id/metadata`) — an
on-demand comparison-review screen, always available, not gated behind a
raised `PendingDecision`. `Enrichment::EditionMetadataCards#build` feeds
the same `Ui::ComparisonCardComponent`: a reference "Edition · in
catalog" card (not selectable) plus one selectable card per
`EnrichmentRecord` source on file — *every* field pickable from *every*
source (unlike `PendingDecision#comparison_cards`, which only makes the
one proposing source's fields selectable — see the 4th selection idiom
above). Submitting applies each ticked field straight from its named
source (`Enrichment::EditionMetadataResolver`) — no `FieldApplier`
conflict gate, the reviewer already chose in front of the full
comparison. Redirects back to the book page with a flash summary
(`layouts/application.html.erb` renders `notice`/`alert`). Header follows
the standard comparison-review shape exactly: badge = a short descriptor
(here the edition's format, standing in for "kind"), h1 = the work title,
subtitle = authors — **don't put the subject in the badge**, that's the
one thing the first cut of this screen got backwards.

**Quick shortcut — right-click the cover.** A small panel rolls out *in
place* from the cover (`cover_picker_controller.js`), not a centered
`<dialog>` — deliberately: a native `<dialog>`'s `showModal()` centers
in the viewport (Tailwind's preflight resets `margin: 0`, which breaks
even that), landing top-left and reading as a stray unstyled box, plus a
full backdrop is more takeover than a two-cover pick warrants. Instead:
a plain `absolute left-0 top-0` panel anchored to a `relative` wrapper
around the cover, `hidden` by default, `scale-95 opacity-0` as its
JS-toggled "closed" transition state (`origin-top-left`, so it visibly
unfurls from the cover's corner) — click-outside and Escape close it,
handled in the controller since there's no native dialog light-dismiss
to lean on. Only wired when `EditionCardComponent#cover_choices` (sources
with a cover on file) is non-empty. Picking a cover submits a single
`"<provider>:cover_image"` pick straight to the same
`EditionMetadataController#update` the full page uses — no separate
endpoint. This is the fast path for "relaxed about trusting an
ISBN-matched ISFDB cover most of the time, but want an easy escape hatch
per book" (docs/INTEGRATIONS.md's cover-conflict addendum).

### `Ui::MarkdownComponent`

Renders stored Markdown (reviews). Styling is the `.markdown` block in
`application.css` — deliberately minimal, grown on demand.

## Screen patterns

### Comparison-review screen

The shape for "here are N candidates, make one structural call." Used by
`pending_decisions/_decision_comparison`,
`pending_decisions/_decision_printing_choice` (candidate ISFDB printings
for a reused ISBN — radio + checkboxes per card) and
`pending_decisions/_decision_edition_reconciliation`. A new review screen
of this kind should be recognisably the same page:

```
#<name>  .w-full.max-w-5xl   data-controller="decision-shortcuts"
├─ .mb-4.flex.flex-wrap.gap-2        badges (conflict kind + any default context)
├─ h1.text-2xl.font-bold             the subject (work title)
├─ p.mb-4.text-sm.text-gray-500      subtitle (author)
├─ form  data-decision-shortcuts-target="accept"
│   ├─ .mb-6.grid.grid-cols-1.items-start.gap-4.lg:grid-cols-3
│   │     └─ Ui::ComparisonCardComponent × N   (flagged card first or last, consistently)
│   ├─ (optional) fieldset            extra structured choice — radio group, legend
│   │                                 in the same uppercase-xs style as a card label
│   └─ button.bg-green-600            "Apply (A)" / "Accept (A)"
└─ .mt-3.flex.gap-3
    ├─ button_to .bg-gray-200         "Reject (R)"   data-…-target="reject"
    └─ link_to .ml-auto               "Back to queue"
```

Rules:

- **The container `id` is the Turbo-Stream swap target.** `resolve`/`accept`
  renders an `advance.turbo_stream.erb` that
  `turbo_stream.replace "<name>"` with the next item's partial — the queue
  advances in place, no navigation (principle 4). Same `id` on the
  `_all_done` empty state so the last decision swaps to "All caught up."
- **Keyboard-first** (principle 3): `data-controller="decision-shortcuts"`
  on the wrapper, `decision_shortcuts_target: "accept"` on the primary
  form, `"reject"` on the reject `button_to`'s form. `A` / `R` submit them
  from anywhere on the page (the controller ignores keystrokes while a
  text input or `<select>` has focus).
- **One primary action.** Nuance goes into form controls *inside* the card
  area (checkboxes) or a single radio `fieldset` above the button — never a
  row of differently-coloured verbs. If there's genuinely a small fixed set
  of structural outcomes, they're radios + one "Apply"; the one
  always-destructive outcome ("Reject") is the separate grey button.
- **Trust the labels.** No explanatory prose block at the foot of the
  screen — a one-line hint next to a radio is fine, a paragraph means the
  labels aren't carrying their weight.

### Queue / index list

`pending_decisions/index` — the one queue, every kind (including
`edition_reconciliation`) filtered from the same index via the kind pills
below. `w-full max-w-3xl`; `<h1>`; an optional one-line description; then a
`divide-y … rounded-lg border` `<ul>` of `<li>` rows, each a full-width
`link_to` (`flex items-center justify-between gap-4 px-4 py-3
hover:bg-gray-50 dark:hover:bg-gray-800`) with the subject on the left and a
`Ui::BadgeComponent` on the right. Filter pills (when a queue has kinds)
are a `flex flex-wrap gap-2` row of `rounded-full px-3 py-1 text-sm` links,
active one in `conflict`.

### "All caught up" empty state

`_all_done` partial, rendered inside the same wrapper `id` so it works as a
Turbo-Stream target. `rounded-lg border border-dashed border-gray-300 p-8
text-center`, a `text-lg font-medium` line, a muted sub-line, a "Back to
queue" link.

## Flash messages

`layouts/application.html.erb` renders `notice`/`alert` as a full-width
bar directly under the header, above `<main>` — plain Rails flash, no
Turbo Stream (it only ever appears after a real page redirect:
`PendingDecisionsController#resolve`'s invalid-resolution alert, or
`EditionMetadataController#update`'s "Updated Cover image,
Publisher." summary). Two variants, one per Rails key:

| key | classes | when |
|---|---|---|
| `notice` | `border-green-200 bg-green-50 text-green-800` (dark: `border-green-900 bg-green-950 text-green-200`) | a successful action |
| `alert` | `border-conflict-200 bg-conflict-100 text-conflict-800` (dark: `border-conflict-900 bg-conflict-900 text-conflict-200`) | something needs the reviewer's attention — reuses the `conflict` token, same as everywhere else a "needs a look" state shows up |

**This is app-wide chrome, not a screen concern** — a controller sets
`notice:`/`alert:` on `redirect_to` and gets the banner for free; no view
needs to know it exists. Added 2026-09-04 alongside `EditionMetadataController`
— before this, `flash` was set in a couple of places (the then-separate
`EditionReconciliationsController`'s invalid-resolution `alert`, since
folded into `PendingDecisionsController#resolve`) but never actually rendered anywhere, a
pre-existing gap.

## Button roles

| role | classes | when |
|---|---|---|
| Primary | `rounded-md bg-green-600 px-4 py-2 font-medium text-white hover:bg-green-700 dark:bg-green-700 dark:hover:bg-green-600` | the one affirmative action per screen (Accept / Apply) |
| Secondary / reject | `rounded-md bg-gray-200 px-4 py-2 font-medium text-gray-800 hover:bg-gray-300 dark:bg-gray-700 dark:text-gray-200 dark:hover:bg-gray-600` | Reject, Cancel |
| Destructive-emphasis | `bg-amber-600 … text-white hover:bg-amber-700` | reserved for a genuinely irreversible/lossy action that still needs doing inline; use sparingly |
| Tertiary | `text-sm text-gray-500 hover:underline` | "Back to queue", nav |

## Dark mode

Every colour utility gets its `dark:` pair, written as the component/view is
built (principle 7) — never a retrofit pass. Follow `prefers-color-scheme`
(the `dark:` variant's default); there is no manual toggle and no plan for
one (single-user app). The `conflict` token already carries both ends
(`100`/`800` light, `900`/`200` dark) — use the token, not a hand-picked
amber, and dark mode comes for free.

## Checklist

Before a new screen merges:

- [ ] Named its job in one sentence (principle 2). Does the layout serve
      *that*, or is it copying a screen with a different job?
- [ ] Composed from `Ui::` components where one exists; any new shared
      visual concept extracted into its own `Ui::` component **with a
      preview and a unit test**, and added to this doc.
- [ ] Custom colours are `@theme` tokens, not raw shades. New token added
      to the table above.
- [ ] Every colour utility has a `dark:` pair.
- [ ] Mobile-first: base classes target the phone, `sm:`/`lg:` add richness.
- [ ] If it's a review/triage screen: one primary action, keyboard targets
      wired, Turbo-Stream advance, container `id` shared with `_all_done`.
- [ ] Form controls are labelled; focus states visible.
- [ ] This doc updated if the screen established or changed a pattern.
