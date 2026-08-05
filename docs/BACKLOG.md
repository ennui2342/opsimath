# Backlog

Things worth coming back to — not designed in full yet, just captured with
enough context to pick up later. Unlike `PHILOSOPHY.md`/`DATA_MODEL.md`/
`INTEGRATIONS.md`, this is a running list, not a settled design.

## Periodic data-cleaning jobs

Recurring jobs that catch things falling through the cracks between the
one-shot mechanisms already built — not new features, just closing the
gap between "attempted once" and "actually resolved."

- **Retry enrichment for editions that missed it.** `GoodreadsSyncJob`
  triggers ISFDB enrichment for a freshly auto-created Edition
  immediately, but it's a one-shot attempt (see
  `GoodreadsSyncJob#enrich_new_edition`) — if the ISBN isn't in the ISFDB
  mirror yet, or the isfdb-adapter call transiently fails, that Edition
  just sits unenriched forever with no automatic retry. Confirmed this
  is a real, non-theoretical gap: after deploying to production
  (2026-08-05), 9 Editions the dev environment's Goodreads sync had
  auto-created were still sitting completely unenriched, simply because
  the bulk `isfdb:enrich_editions` task was never re-run in dev after
  they were created. `Enrichment::IsfdbEditionEnricher`'s existing scope
  (`Edition` has an ISBN, no `EnrichmentRecord` yet) already correctly
  identifies these — the gap is purely that nothing re-checks it on a
  schedule. Likely doesn't need new code, just a `config/recurring.yml`
  entry for the existing `IsfdbEnrichmentJob`, at a much lower frequency
  than the hourly Goodreads sync (ISFDB's own mirror only updates on a
  new dump release, not continuously — a monthly or quarterly cadence is
  probably plenty, not hourly).
