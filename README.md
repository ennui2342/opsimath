# opsimath

A personal system for cataloging a physical book collection (mostly SF
paperbacks, often pre-ISBN), tracking reading — including rereads — and
managing short reviews published as **scifipraxis** across Instagram,
Goodreads, and a personal website.

Spiritual fork of [librarium](https://github.com/FireBall1725/librarium),
rebuilt from first principles in Ruby for a single collector rather than
a shared/multi-tenant system. See `docs/PHILOSOPHY.md` for what's carried
over, what's deliberately dropped, and why.

## Status

Documentation phase — data model first, before any code. Nothing here runs
yet.

## Docs

- [`docs/PHILOSOPHY.md`](docs/PHILOSOPHY.md) — why this project exists, the
  guiding principles, what it's explicitly not trying to be.
- [`docs/DATA_MODEL.md`](docs/DATA_MODEL.md) — the entity model: Work,
  Edition, Copy, Reading, Review, and how they relate.
- [`docs/INTEGRATIONS.md`](docs/INTEGRATIONS.md) — the Goodreads import/
  sync design: the first real feature being built, ahead of any UI.

## Stack

Ruby 4.0 / Rails 8.1 — chosen over the project's original Python starting
point; see `docs/PHILOSOPHY.md` principle 17 for why. Postgres. Hotwire
(Turbo + Stimulus) and Tailwind (v4, via `importmap-rails`/
`tailwindcss-rails` — no Node toolchain) for the web UI, with Turbo Native
in view for an eventual mobile client. Solid Queue for scheduling/
background jobs, PaperTrail for versioning, Rails 8's built-in
authentication generator for a single-owner login gate — see principles
13, 15, 18, and 19. Minitest + fixtures + Capybara system tests (Rails
defaults) for testing. Docker for local development, to keep the host OS
clean. Eventual deployment target is the k8s homelab cluster (same as
librarium and `isfdb-adapter`) — not decided further than that yet.

`~/projects/isfdb-adapter` (a separate, already-deployed Python/FastAPI
service opsimath talks to over HTTP) is unaffected by this — it doesn't
need to share a language with opsimath.
