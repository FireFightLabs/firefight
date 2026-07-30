# Contributing to Firefight

Thanks for your interest in contributing. This guide covers the full development setup and the conventions PRs are expected to follow.

## Requirements

We use [mise](https://mise.jdx.dev/) to pin language and tool versions. After installing mise, run `mise install` from the repo root to get the right Ruby.

- Ruby (pinned in `.ruby-version`)
- PostgreSQL 18.3
- Node (for the frontend toolchain)
- libvips (Active Storage resizes images through it, and Rails loads it at boot)

Install libvips with `brew install vips` on macOS, or `apt install libvips` on Debian and Ubuntu. The app will not boot without it.

## PostgreSQL via Docker

Production runs PostgreSQL 18.3, so we run the same version locally to keep dev/prod parity. Start it with:

```sh
docker run -d \
  --name firefight-postgres \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=postgres \
  -p 5432:5432 \
  -v firefight-postgres-data:/var/lib/postgresql \
  postgres:18.3
```

Stop and start it later with `docker stop firefight-postgres` and `docker start firefight-postgres`. The named volume `firefight-postgres-data` keeps your data across restarts.

Then create the development and test databases:

```sh
bin/rails db:prepare
bin/rails db:prepare RAILS_ENV=test
```

Development uses four databases on this one Postgres server — the primary plus separate `cache`, `queue`, and `cable` databases for Solid Cache/Queue/Cable, mirroring production. `db:prepare` creates all of them automatically and loads each from its own schema file (`db/schema.rb`, `db/cache_schema.rb`, `db/queue_schema.rb`, `db/cable_schema.rb`) — no manual `createdb` needed. Test runs on a single database.

## Environment variables

Copy `.env.example` to `.env` and fill in the values. At minimum you need the Slack credentials and Active Record encryption keys.

Generate the encryption keys (run once per developer machine):

```sh
bin/rails db:encryption:init
```

Copy the three output values into your `.env`:

```sh
ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=<primary_key>
ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=<deterministic_key>
ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=<key_derivation_salt>
```

These keys encrypt sensitive columns (OAuth tokens). Keys only need to match the database they created data in.

## Slack app for development

Each developer uses their own Slack workspace and their own Slack app. Create an app at [api.slack.com/apps](https://api.slack.com/apps) in a workspace you control, and put its credentials (`SLACK_CLIENT_ID`, `SLACK_CLIENT_SECRET`, `SLACK_SIGNING_SECRET`, `SLACK_TEAM_ID`) in your `.env`.

## Local development tunnel (Cloudflare Tunnel)

Slack needs a public URL to deliver slash commands and interactions to your local Rails server. We use [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/).

Quick start (ephemeral hostname, rotates each run):

```sh
brew install cloudflared
cloudflared tunnel --url http://localhost:3000
```

Copy the printed `*.trycloudflare.com` URL into your Slack app manifest's request URLs.

For day-to-day dev, prefer a named tunnel so the hostname stays stable across restarts (no need to re-paste URLs into the Slack manifest each session):

```sh
cloudflared tunnel login                          # authenticate, pick a Cloudflare-managed domain
cloudflared tunnel create firefight-dev           # creates a tunnel + credentials file
cloudflared tunnel route dns firefight-dev dev.<your-domain>
cloudflared tunnel run --url http://localhost:3000 firefight-dev
```

Then point your dev Slack manifest at `https://dev.<your-domain>/api/v1/commands` and `/api/v1/interactions`.

Rails blocks unknown hosts by default, so add your tunnel hostname to `.env`:

```sh
ALLOWED_HOSTS=dev.<your-domain>,*.trycloudflare.com
```

`config/environments/development.rb` reads `ALLOWED_HOSTS` (comma-separated) and appends each entry to `config.hosts`.

## Active Storage (Cloudflare R2)

Set these environment variables to archive incident files to R2:

- `ACTIVE_STORAGE_SERVICE=r2`
- `R2_ACCESS_KEY_ID`
- `R2_SECRET_ACCESS_KEY`
- `R2_ENDPOINT` (for example `https://<account-id>.r2.cloudflarestorage.com`)
- `R2_BUCKET`
- `R2_REGION` (use `auto` for R2)
- `R2_REQUEST_CHECKSUM_CALCULATION` (recommended: `when_required`)
- `R2_RESPONSE_CHECKSUM_VALIDATION` (recommended: `when_required`)

## Running the test suite

`bin/ci` runs everything CI runs: rubocop, bundler-audit, brakeman, the test suite (parallel), system tests, and seeds.

For day-to-day work:

```sh
bin/rails test               # full unit/integration suite
npm run typecheck            # TypeScript strict check
npm run lint                 # ESLint
```

All of these must pass before a PR is ready for review. Fork PRs run the full CI suite — no secrets are required.

## Conventions

- **Architecture**: read `CLAUDE.md` at the repo root for the core rules, then the relevant deep dive in `docs/` — [architecture](docs/architecture.md) (layer hierarchy, entry points, services, adapters), [frontend](docs/frontend.md), [workflows](docs/workflows.md), and [api](docs/api.md). PRs that skip layers or duplicate entry-point logic will be asked to restructure.
- **Code style**: enforced by rubocop and ESLint. No unnecessary comments; no magic strings (use the constants in `Identifiers` and model constants).
- **Tests**: every behavior change comes with tests. Never use `Model.last` in tests (parallel execution); build platform objects (`Command`, `Interaction`) instead of raw hashes.
- **Schema changes**: PRs touching `db/migrate` are auto-labeled `migration` and surface in release notes. Migrations must be safe to run with `bin/rails db:prepare` and never require manual SQL.
- **Commits and PRs**: small, focused PRs with a clear description of the why. CI must be green.

## License

Firefight is licensed under [AGPL-3.0](LICENSE). By contributing, you agree that your contributions will be licensed under the same terms.
