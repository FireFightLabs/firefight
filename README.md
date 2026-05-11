# Firefight

Incident management platform built with Rails 8.1.

## Requirements

We use [mise](https://mise.jdx.dev/) to pin language and tool versions. After installing mise, run `mise install` from the repo root to get the right Ruby.

- Ruby 3.4.7 (pinned in `.ruby-version`)
- PostgreSQL 18.3
- Node (for the frontend toolchain)

## PostgreSQL via Docker

Production runs PostgreSQL 18.3, so we run the same version locally to keep dev/prod parity. Start it with:

```sh
docker run -d \
  --name firefight-postgres \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=postgres \
  -p 5432:5432 \
  -v firefight-postgres-data:/var/lib/postgresql/data \
  postgres:18.3
```

Stop and start it later with `docker stop firefight-postgres` and `docker start firefight-postgres`. The named volume `firefight-postgres-data` keeps your data across restarts.

Then create the development and test databases:

```sh
bin/rails db:prepare
bin/rails db:prepare RAILS_ENV=test
```

## Local development tunnel (Cloudflare Tunnel)

Slack needs a public URL to deliver slash commands and interactions to your local Rails server. We use [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) since we're already on Cloudflare for R2.

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

## Running the test suite

`bin/ci` runs rubocop, bundler-audit, brakeman, the test suite (parallel), system tests, and seeds.

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
