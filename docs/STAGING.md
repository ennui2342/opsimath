# Staging / UAT

opsimath deploys straight to production from `master` (Flux reconciles the
image — see the repo README and `docs/PHILOSOPHY.md` principle 13/21).
There is no separate deployed staging environment. Instead, staging is a
**local stack that runs the real production artifact**, for a hands-on
UAT pass before pushing.

## What it is

`docker-compose.uat.yml` builds the production `Dockerfile` (multi-stage,
non-root, gems + assets baked in) and runs it as `RAILS_ENV=staging` — a
faithful clone of production (`config/environments/staging.rb`), the only
departures being the ones that assume a TLS-terminating proxy upstream
(this stack is plain HTTP on `localhost:3001`).

This is deliberately different from `docker-compose.yml` (the dev stack:
bind-mounted source, hot reload, `development`). Dev is for building
features fast; UAT is for catching what dev mode hides — eager-load
failures, asset-build problems, caching behaviour, anything that only
shows up in the built image.

The two stacks have separate compose projects, volumes and ports, so they
run side by side:

| | dev (`docker-compose.yml`) | UAT (`docker-compose.uat.yml`) |
|---|---|---|
| URL | http://localhost:3000 | http://localhost:3001 |
| Rails env | development | staging |
| Source | bind mount, live reload | baked into the image |
| Data | `postgres_data` / `bundle_data` | `uat_postgres_data` / `uat_storage` |

## Workflow

```bash
bin/uat            # build + (re)start the stack on the current working tree
bin/uat-db-pull    # mirror live production data (DB + cover images) into it
```

Then open http://localhost:3001 and click through the change.

`bin/uat` **rebuilds the image every run**. Docker's layer cache makes
that near-instant when nothing changed; when the Gemfile, a migration, an
asset or any app code changed, that layer rebuilds — so the stack is
never stale codewise. Run it again after every change you want to UAT.

`bin/uat-db-pull` `pg_dump`s the live `app_production` database and `tar`s
the Active Storage cover images out of the production pod, then loads both
into the UAT stack. It needs `kubectl` pointed at the homelab cluster
(read-only is enough — it never writes to production). Re-run it whenever
you want to refresh against current live data; it drops and recreates the
local `app_staging` each time.

```bash
docker compose -f docker-compose.uat.yml logs -f web        # tail logs
docker compose -f docker-compose.uat.yml exec web ./bin/rails console
docker compose -f docker-compose.uat.yml down               # stop (keeps data)
docker compose -f docker-compose.uat.yml down -v            # stop + wipe data
```

## Notes

- **Master key.** `bin/uat` reads `config/master.key` and passes it as
  `RAILS_MASTER_KEY` (the key is git-ignored and not baked into the
  image). Running `docker compose -f docker-compose.uat.yml …` directly
  without that env set fails loudly.
- **Migrations.** The web container's entrypoint runs `db:prepare` on
  boot, so `bin/uat` applies any migrations the working tree is ahead of
  the loaded data on. `bin/uat-db-pull` also fixes up
  `ar_internal_metadata` so the prod dump doesn't trip
  `ActiveRecord::EnvironmentMismatchError`.
- **Data sensitivity.** The dump is copied as-is — it's a single-user
  homelab app and the data is your own reading history. `sessions` and
  `api_tokens` come across too; if that ever matters, truncate them after
  a pull.
- **cover-compare.** Uses the published `opsimath-cover-compare:latest`
  image (the same artifact k8s runs). It's best-effort — enrichment
  tolerates it being down.
