# UI & design system principles

This document exists for the same reason `PHILOSOPHY.md` does — so a new
screen or component gets checked against *why* the frontend is shaped
the way it is, not just against whatever the last view happened to look
like. Kept separate from `PHILOSOPHY.md` deliberately: that document is
already long and scoped to the data model and backend architecture,
and the whole point of writing this down now is to let the design
system grow as its own thing, the same reason `INTEGRATIONS.md` split
off rather than growing inside `DATA_MODEL.md`/`PHILOSOPHY.md`.

## What this is

opsimath had zero UI beyond the Rails 8 auth scaffold until the
`PendingDecision` review queue and the book page (`docs/BACKLOG.md`
tracked the need; this is where the actual design decisions live). This
document was written *before* those two screens, not after, on the
premise that the first screens set the pattern every later one copies —
worth getting the defaults right before there are a dozen views to
retrofit.

## Principles

### 1. Mobile-first, progressively layered

Write the base styles for the smallest viewport; add richness at
`sm:`/`md:`/`lg:` breakpoints; never the reverse (build for desktop,
then cram it into a phone screen as an afterthought). This is Tailwind's
own native philosophy — unprefixed utility classes already *are* the
mobile-first base, breakpoint-prefixed ones are the progressive layer on
top — so committing to it explicitly costs nothing beyond writing it
down.

Not just best-practice box-ticking: `PHILOSOPHY.md` principle 17 already
names Turbo Native as a real future direction for a mobile client, and a
personal collector plausibly wants to check or add a book from a phone
in a shop, not only from a laptop at a desk. A responsive web UI today
is also the cheapest possible step toward that eventual native client —
Turbo Native wraps a Hotwire web app in a native shell, so a UI that
already works properly at phone width is most of the way there already.

### 2. Every screen has a named job, and the design serves *that* job

Stated explicitly because the first two real screens want opposite
things from each other:

- The `PendingDecision` review queue's job is **fast, confident, repeated
  decisions** — someone working through a backlog of a hundred-plus
  bibliographic conflicts in one sitting. Its design optimizes for
  throughput: keyboard-driven, minimal clicks, only the information
  actually needed to decide, one decision flowing into the next with no
  dead time in between.
- The book page's job is **browsing/reference** — looking something up,
  admiring a cover, checking what else is in a series. Its design
  optimizes for completeness and calm reading, not speed; there's no
  "next book" to rush toward.

Naming the job before designing the screen stops a future screen from
copying the wrong pattern by default — cramming a browsing page with
review-queue urgency (constant calls to action, dense diff rows) would
be as wrong as making a triage screen leisurely and click-heavy just
because that's how the book page happened to look.

### 3. The review queue is keyboard-first, not mouse-first

Direct consequence of principle 2 for that specific screen, not a
general rule for every screen. Accept/reject are bound to keypresses,
not only click targets; focus is managed so the next decision is
immediately actionable with no pointer movement required in between.
This isn't a nicety layered on afterward — reviewing 500+ real
`PendingDecision`s by mouse click alone is exactly the "hard work"
this whole feature exists to remove, the same way a fast triage tool
(an inbox, a code-review queue, a moderation dashboard) always ends up
keyboard-driven once the volume is real.

### 4. Turbo Streams for the high-frequency interaction; plain pages everywhere else

The review queue's accept/reject → next-item loop is exactly Turbo
Streams' proven use case: swap the current decision for the next one in
place, no full-page navigation, still zero custom JS framework — a real
need earning real infrastructure, not adopting Turbo Streams
speculatively because it's available. The book page has no equivalent
throughput need, so it stays a plain Turbo-Drive page load; reaching for
Streams there would just be complexity with nothing to pay for it.

### 5. `ViewComponent`, not ad-hoc partials

Adopted for the same reason `PHILOSOPHY.md` principle 16 already governs
the backend: is this core/differentiating, or would a mature library do
it better? A shared-component convention for buttons, badges, diff rows,
and cards isn't opsimath's differentiation any more than a job scheduler
or an audit-history table is — and `ViewComponent` is the mature,
Rails-aligned, widely-used answer (the same "buy, don't build" call
already made for Solid Queue over a hand-rolled scheduler and PaperTrail
over a hand-rolled version history).

Concretely, each component gets:

- Its own class + template under `app/components/`, tightly scoped
  (one visual concept per component), namespaced under `Ui::` for
  generic, reusable pieces as they accumulate.
- A `Preview` class under `test/components/previews/`, browsable at
  `/rails/view_components` in development — a Storybook-like catalog
  with no separate tool to install or maintain. This is the concrete
  mechanism that makes "grow the design system as its own thing" real:
  a component can be looked at, in every state it supports, without
  needing the full page it happens to be used on.
- A unit test (`render_inline`, per principle 10 below) — a component
  is exactly the kind of small, reused-everywhere unit where a silent
  regression is expensive and a test is cheap.

### 6. Tailwind v4 theme tokens, named, not raw utility values repeated everywhere

A `@theme` block in `app/assets/tailwind/application.css` names the
actual semantic vocabulary this app needs — starting with a `conflict`
color used consistently anywhere a `PendingDecision` shows up — rather
than each view independently picking its own shade of amber or red.
Cheap to do now, while there are only a handful of views; the entire
point of having named tokens is moot if it's deferred until dozens of
views already have their own copy-pasted color choices to reconcile.

### 7. Dark mode from day one

Tailwind's `dark:` variant, following `prefers-color-scheme`, wired into
components as they're built rather than retrofitted later. Cheap now
(one variant per color utility, while the component library is still
small); expensive later (an audit pass across every view/component ever
written). A real want, not just best practice: reading and reviewing at
night is a plausible, ordinary usage pattern for a personal reading app,
not a hypothetical edge case.

### 8. Accessible by default

Semantic HTML, labeled form controls, visible focus states — table
stakes generally, and directly load-bearing for principle 3
specifically: a review queue that isn't genuinely keyboard-navigable,
with visible focus and real form labels, fails its own stated job, not
just an accessibility checklist.

### 9. A fast-decision interface needs a low-friction undo

Named now even though not fully built in the first slice: the whole
point of principles 2/3 is *speed*, and speed raises the real cost of a
misclick. The undo mechanism mostly already exists at the data layer —
`PendingDecision.status` is a plain enum, trivially revertible back to
`pending`, and `PaperTrail` already versions whatever `Edition` field an
acceptance changes (`DATA_MODEL.md`'s `EnrichmentRecord`/`PendingDecision`
sections) — so a lightweight "undo my last decision" affordance is a
natural next increment once the base accept/reject flow is proven out
in real use, not a redesign or a new mechanism.

### 10. Extend principle 21's testing stance to the view layer

`PHILOSOPHY.md` principle 21 tests the data-integrity/business-logic
layer where a silent bug does real damage, and skips ceremony for plain
scaffolding with no subtle behavior to pin down. Same rule, applied to
components: a shared, reused-everywhere `Ui::` component earns a real
unit test (via `ViewComponent::TestHelpers#render_inline`); a
one-off page composed from already-tested components doesn't need its
own exhaustive rendering test beyond a plain "does it load" request
spec.

## Non-goals (for now)

- A full component library built ahead of need — components are added
  when a real screen needs them, not spun up speculatively because
  "a design system should have one."
- A generic theming/white-label system — this is a single-user app;
  `dark:`/`light:` is the only real variation that matters.
- Editing/write forms as their own design problem — deferred until a
  screen actually needs one; the review queue's accept/reject is a
  narrow, specific write action, not a general form-building pattern
  yet.
