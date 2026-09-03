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
amber, `:success` green). Genre/subject/tag chips on the book page;
kind/shelf/status markers on the review queues. Stack multiple in a
`flex flex-wrap gap-2` row (e.g. a `:conflict` "edition reconciliation" next
to a `:default` shelf name).

### `Ui::ComparisonCardComponent`

One card in a **comparison-review** layout. Dumb renderer — the model method
that builds the cards owns all the "which fields, which are selectable"
logic (`PendingDecision#comparison_cards`,
`EditionReconciliation#comparison_cards`). Both feed it the same
`Ui::ComparisonCardComponent::Card` / `::FieldRow` structs.

`Card` knobs:

| knob | effect |
|---|---|
| `label` | uppercase card header |
| `meta` | date shown top-right of the header (anything `to_date`-able) |
| `proposed` | flags the card that raised the decision — conflict ring + tinted header |
| `cover` | an ActiveStorage attachment to show |
| `cover_url` | a remote image URL to show instead (incoming feed rows have no attachment) |
| `cover_selectable` | render the "Apply this cover" checkbox over the cover |
| `show_empty_cover` | draw the dashed "No cover" placeholder when nothing is attached |
| `fields` | `FieldRow`s; a `selectable` one gets a pre-checked `fields[]` checkbox and the conflict highlight |
| `identifiers` | `[[label, value], …]` mono footer |
| `info_note` | small muted line at the card foot ("Reference only …") |
| `select_name` / `select_value` / `selected` | turns the whole card header into a radio — picks this card among its siblings; a checked card takes the same conflict ring as `proposed` (pure CSS, `has-[:checked]:`) |

Two selection idioms, don't mix them on one card:

- **Per-field checkboxes** (`FieldRow#selectable`) — "which of these values
  do I want", `PendingDecision`. Submits `fields[]`.
- **Whole-card radio** (`select_name`) — "which of these candidates is it",
  `EditionReconciliation`. Submits one value under `select_name`.

### `Ui::EditionCardComponent`

One edition (a printing), laid out the same way everywhere it appears —
`app/components/ui/edition_card_component.rb`, `initialize(edition:)`. The
shape:

```
┌────────┬─────────────────────────────────┐
│ [cover]│  Mass market            ← bold  │   format_detail → format → "Edition"
│  h-32  │  Grafton · 1988 · 471 pages      │   publisher · year · pages, blanks dropped
│  or a  │                                  │
│ dashed │  ISBN-13 9780…  ISBN-10 0586…    │   mono footer, EditionIdentifier order
│  "No   │  ISFDB 12345↗  Goodreads 1343↗   │   ISFDB/Goodreads linked, ISBNs plain
│ cover" │                                  │
└────────┴─────────────────────────────────┘
```

- Cover keeps the page's existing size (`h-32` on the web work page); a
  missing cover gets the same dashed **"No cover"** placeholder
  `ComparisonCardComponent` uses, so a grid of edition cards aligns.
- The identifier footer is the **same treatment** as
  `ComparisonCardComponent`'s (`flex flex-wrap`, mono, `text-xs`,
  `<b>label</b> value`). Order and labels come from
  `EditionIdentifier::DISPLAY_ORDER` / `#label`; a link appears only when
  `EditionIdentifier#external_url` is non-nil (ISFDB, Goodreads) — ISBNs
  are deliberately unlinked (no single right destination).

**This layout is shared with the pocket app** (`docs/MOBILE.md`), which
can't use a ViewComponent — it builds cards in plain JS
(`pocket.js` `editionCardHtml` / `idFooter`) against CSS classes in
`pocket.css` (`.edition`, `.edition .fmt`, `.edition .ids`). The two
implementations track this one spec: same format→publisher→ids hierarchy,
same identifier order, same ISFDB/Goodreads-only linking. `pocket.js`'s
`ID_URL` map mirrors `EditionIdentifier::EXTERNAL_URL_BY_TYPE`; keep them
in step. The snapshot carries the ids per edition
(`Mobile::SnapshotBuilder` `editions` table: `isbn10/isbn13/isfdb/goodreads`).

When you change the edition layout, change it in both places (or write
down why they diverge) — same rule as `feedback_goodreads_path_parity`
for the sync paths.

### `Ui::MarkdownComponent`

Renders stored Markdown (reviews). Styling is the `.markdown` block in
`application.css` — deliberately minimal, grown on demand.

## Screen patterns

### Comparison-review screen

The shape for "here are N candidates, make one structural call." Used by
`pending_decisions/_decision_comparison` and
`edition_reconciliations/_reconciliation`. A new review screen of this kind
should be recognisably the same page:

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

`pending_decisions/index`, `edition_reconciliations/index`.
`w-full max-w-3xl`; `<h1>`; an optional one-line description; then a
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
