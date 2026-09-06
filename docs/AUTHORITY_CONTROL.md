# Authority control

A curated set of **preferred forms** of names and their **variants**, so
enrichment resolves textual data to one authorized form instead of
raising a `PendingDecision` every time a source spells a name a different
way. This is the library practice of the same name
(<https://en.wikipedia.org/wiki/Authority_control>) — an authorized
heading with "see-from" cross-references — scoped down to what a personal
catalogue needs.

opsimath already leans on bibliographic standards elsewhere (Thema for
genre, ONIX Codelist 150 for format). This is the mechanism that keeps a
*controlled field* — a record column drawn from a vocabulary — pointing
at agreed terms rather than whatever string a source happened to send.

**First and only vocabulary today: `publisher`.** The design is generic
because the same shape is coming for others (contributor pen-names —
`Iain Banks` / `Iain M. Banks`, `James Tiptree, Jr.` / `Alice Sheldon` —
and series titles are the obvious next two).

Built 2026-09-06 (Mark: *"a mapping that we can add to that would
maintain a list of variant publisher names and the preferred name… the
algorithmic approach can then be retired as it has more potential for
mistakes"*, then: *"should we frame this generically as implementing the
first of maybe many authority control"*).

## Vocabulary

| term | meaning |
|---|---|
| **authority file** | the whole controlled list for one vocabulary |
| **term** (`AuthorityTerm`) | one concept — its preferred form and its variants (SKOS: a `Concept` with one `prefLabel`, many `altLabel`) |
| **preferred name** (`preferred_label`) | the authorized form; what the catalogue stores (`Tor.com`) |
| **variant** (`AuthorityVariant`) | a non-preferred form that resolves to the term (`Tordotcom`) |
| **controlled field** | a record column drawn from an authority file (`Edition.publisher`) |
| **establish** | add a term / register a variant |
| **retract** | remove a term or variant — and re-check what depended on it |

## Model

Two tables, both vocabulary-agnostic:

```
AuthorityTerm
  vocabulary        "publisher"   (indexed; validated against Authority::VOCABULARIES)
  preferred_label
  unique (vocabulary, preferred_label)
  has_many :authority_variants, dependent: :destroy

AuthorityVariant
  authority_term_id  fk
  vocabulary         denormalised from the term — so "one meaning per string
                     per vocabulary" is a real DB unique index, not an app check
  label              the variant as seen: "Pan Macmillan UK"
  normalized_label
  unique (vocabulary, normalized_label)
```

- **Every term carries a self-variant** (`label == preferred_label`), kept
  in sync when the preferred label is renamed, so `Authority.resolve` is a
  single lookup that also matches the preferred form itself.
- **`Authority.normalize(str)`** — case, the `&`/`and` connector, and every
  non-alphanumeric folded away. Lifted verbatim from
  `Enrichment::IsfdbEditionEnricher#normalize_name` (which now delegates to
  it) so the authority file and the enricher's own string comparison agree
  on what "the same string" means. `"Harper Voyager (UK)"` →
  `"harpervoyageruk"` — note this does **not** unify `HarperVoyager` and
  `Harper Voyager (UK)`; that needs an explicit variant, or the enricher's
  mechanical `(UK)`-tail rule (see below).
- **`Authority.resolve(vocabulary, str) → preferred_label | nil`** — one
  indexed lookup on `AuthorityVariant`.
- **`AuthorityTerm#register_variant(label)`** is idempotent, and *raises*
  (`AuthorityTerm::Conflict`) rather than silently re-point a string
  already used by another term in the same vocabulary.

## The vocabulary registry

`Authority::VOCABULARIES = { "publisher" => "Authority::Publishers" }`.

Each vocabulary registers a handler that owns its catalogue-specific
behaviour behind one interface:

```
Authority::Publishers
  .label                    → "Publishers"                (settings screen)
  .controlled_fields        → ["Edition#publisher"]       (informational)
  .apply(term)              → after a term/variant is established   → Result
  .retract(removed_labels:, preferred_label:) → after removal       → Result
  .usage(term)              → { editions:, pending_conflicts: }     (settings screen)
```

Adding "series" or "contributor" later is one handler class plus a
registry entry. The model, `Authority.resolve`, and the settings
controllers need no change.

## How the publisher vocabulary behaves

### Resolution — `IsfdbEditionEnricher#plan_publisher`

Order of checks, best to worst:

1. same normalised string
2. **the authority file** — `Authority.resolve("publisher", …)` says both
   strings resolve to one term. This is the home for every equivalence a
   string rule can't derive (`Tom Doherty Associates` = `Tor`, `Millenium`
   = `Millennium`). Verdict: the catalogue value is refined to the
   preferred form (or left alone if it's already preferred).
3. mechanical, generalisable string rules the file shouldn't carry one
   entry at a time:
   - the longer name is an imprint/parent form joined by `/` or `&`
     (`Gollancz` vs `Gollancz / Orion`)
   - the only difference is a bracketed/comma qualifier tail
     (`Orbit` vs `Orbit (Hachette)`)
   - the only difference is a trailing **generic corporate-form word**
     (`Ace` vs `Ace Books`, `DAW` vs `DAW Ltd`) —
     `NON_DISTINGUISHING_PUBLISHER_WORDS`, now narrowed to just:
     `books book press publishing publications publishers publ editions
     edition ltd limited inc incorporated co company corp corporation plc
     pty gmbh`
4. otherwise → `:conflict` (a `PendingDecision`)

**What was retired** (Mark, 2026-09-06 — *"deconstruct the fuzzy rules
into a managed list, keep only the deterministic ones"*): the old
`NON_DISTINGUISHING_PUBLISHER_WORDS` list also swallowed descriptive and
territorial words — `science`, `fiction`, `fantasy`, `sf`, `us`, `uk`,
`gb`, `london`, `paperbacks`, `hardcover`, `group`, `house`, `the`. Those
were the guessy part. Now `Gollancz` vs `Gollancz Paperbacks`,
`Tor` vs `Tor Science Fiction`, `Panther` vs `Granada` all go to review —
and become one-line authority-file entries if they're genuinely the same
imprint to you.

`#publisher_equivalent?` (used by `same_edition?` / `cluster_candidates`)
also consults the authority file. And `#candidate_fields` (what an
`enrichment_printing_choice` accept writes) canonicalises the publisher —
so the catalogue converges on preferred forms over time, not just on new
conflicts.

### Establishing a term — `Authority::Publishers.apply`

One transaction:

1. **Rewrite editions** — every `Edition` whose `publisher` string is one
   of this term's variants takes the preferred form. `field_sources` is
   left as-is (the value is canonicalised, not re-sourced). Mark:
   *"let's rewrite. The data is always recoverable in the metadata
   records."*
2. **Re-enrich the affected editions** — each is put back through
   `IsfdbEditionEnricher.reprocess` (replays the stored ISFDB payload, no
   network). With the term in place, `plan_publisher` no longer conflicts,
   so `SourceRecorder.integrate` commits any safe fills that were held
   hostage by the publisher conflict and `resolve_stale_conflict` closes
   the decision — the same mechanism used everywhere else.
3. **Prune** — a *bundled* decision that survives (it had other
   conflicting fields) keeps its original field list, because
   `SourceRecorder.create_bundled_decision` reuses a decision without
   refreshing it. So `apply` explicitly drops `"publisher"` from
   `payload["fields"]` once the enricher agrees it's settled.
4. **Notify** — `Notifications::Event(kind: :authority_control)` with the
   preferred name, variants, and the counts.

### Retracting — `Authority::Publishers.retract`

**No rollback.** Mark's call (*"we should rerun enrichment against those
records and let it flag up the conflicts again"*): the catalogue keeps
whatever value it holds, and the affected editions — those whose current
`publisher`, or whose ISFDB `EnrichmentRecord` publisher, resolved through
the removed entry — are re-enriched. Without the variant, `plan_publisher`
sees the strings differ again and raises a conflict *where one genuinely
exists*. No value-restoration logic, symmetric with `apply`, and
consistent with how every other enrichment-rule change already propagates
(`isfdb:reenrich_editions`).

## UI

### Inline — the review screen

`PendingDecision#authority_row` puts a small `≡` on the proposed card's
**publisher** row, but only when `IsfdbEditionEnricher.plan_publisher_for`
agrees it's a *genuine* conflict (not a refine bundled with another
field's real conflict). It rolls out a panel — the `cover_picker`
interaction (opens in place, closes on outside-click / <kbd>Esc</kbd>),
**not** a centred `<dialog>` — to pick the preferred form (on-file value /
ISFDB value / free text). Both strings become variants.

The panel is **not** a nested `<form>` (the whole review screen is
already one `form_with`, and forms don't nest — the browser drops the
inner tag). `authority_panel_controller.js` collects the values and
`POST`s via `fetch`, then hands the Turbo Stream response to
`Turbo.renderStreamMessage` — same net effect as a `data-turbo-stream`
form. The response re-renders the decision (publisher now gone from the
bundle) or advances to the next one.

### Settings — `/settings/authorities`

opsimath's first settings section. `/settings/authorities` lists the
vocabularies; `/settings/authorities/publisher` is the publisher
authority file — preferred names alphabetically, variant chips, the
`usage` counts, establish/rename/retract, add/remove variant, and a
**Re-scan pending conflicts** button (`AuthoritiesController#rescan` —
re-runs `apply` over every term, for when variants were added directly
here or new conflicts have since arrived).

`Settings::AuthorityTermsController` / `AuthorityVariantsController` are
generic — scoped by `:vocabulary`, delegating the catalogue work to
`Authority.handler(vocabulary)`.

## Deferred

- **A second vocabulary** — the model and settings are built to take it;
  wiring contributor pen-names or series titles is a follow-up.
- **Term-to-term relationships** (SKOS `broader` / `related`) — publishers
  don't use them (an imprint is its own term; `Panther`, `Granada`,
  `Grafton` stay separate). The model leaves room.
- **Negative assertions** ("X is *not* Y", to force a split the mechanical
  rules would merge) — possible later.
- **Seeding from LCNAF / VIAF / Wikidata** — start hand-curated; a bulk
  import against a real authority file is a future option and the model
  is ready for it.
- **An audit table** beyond the notification.

See also `docs/DATA_MODEL.md` (`AuthorityTerm` / `AuthorityVariant`),
`docs/INTEGRATIONS.md` (the reused-ISBN publisher addendum).
