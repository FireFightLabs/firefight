# Self-hosting Firefight

Firefight runs as a single container against a Postgres database. This guide takes you from nothing to a working install with `docker compose`, and then covers upgrades, backups, and running it some other way.

Budget about twenty minutes. Most of it is creating the Slack app.

## Before you start

- **A machine with Docker.** Two cores and 2 GB of memory is enough for a small team.
- **A hostname pointing at it.** Firefight needs to be reachable over HTTPS at a real domain before it works at all, because Slack refuses to deliver events to anything else. Point an A record at the machine and let it propagate first.
- **Ports 80 and 443 open.** Caddy uses 80 to answer the Let's Encrypt challenge and 443 to serve.
- **Permission to install a Slack app** in the workspace you want to use it in.

## 1. Create the Slack app

Firefight ships the app definition it needs, so you do not have to click through scopes.

Open [`config/slack_manifests/production.yml`](config/slack_manifests/production.yml) and replace every `slack.firefight.app` and `app.firefight.app` with your own hostname. There are five URLs: the two slash commands, the events request URL, the interactivity request URL, and the two OAuth redirect URLs.

Then go to [api.slack.com/apps](https://api.slack.com/apps), choose **Create New App**, pick **From a manifest**, select your workspace, and paste the edited YAML.

From the app's **Basic Information** page, copy the **Client ID**, **Client Secret**, and **Signing Secret**. You need all three in the next step.

Do not install the app yet. Firefight installs it for you at the end, which is how it gets its bot token.

## 2. Generate the secrets

Three of these come out of the Firefight image itself.

```sh
docker run --rm ghcr.io/firefightlabs/firefight:latest bin/rails secret
docker run --rm ghcr.io/firefightlabs/firefight:latest bin/rails db:encryption:init
```

The first prints one long string, which is your `SECRET_KEY_BASE`. The second prints three, which are the Active Record encryption keys.

> **Keep the encryption keys somewhere safe.** Incident channel messages, integration credentials and agent tokens are all encrypted at rest with them. They cannot be regenerated, and without them that data is gone.

## 3. Configure and start

Copy the three files from this repository next to each other on the machine: `docker-compose.yml`, `Caddyfile`, and `.env.selfhost.example`.

```sh
cp .env.selfhost.example .env
```

Fill in `.env` with your hostname, a Postgres password of your choosing, the secrets from step 2, and the three Slack values from step 1. Leave `ANTHROPIC_API_KEY` empty if you do not want the AI features, and leave `SLACK_TEAM_ID` empty unless you want to lock sign-in to one workspace.

```sh
docker compose up -d
docker compose logs -f firefight
```

The first boot creates four Postgres databases and runs the migrations, so give it a minute. Caddy gets a certificate at the same time. When the logs settle, open `https://your-host` and you should see the sign-in page.

## 4. Install into Slack

Sign in with Slack from that page. Firefight walks you through installing the bot into your workspace, and once that finishes it creates your workspace with a default set of severities, statuses, incident types and roles.

Run `/ff new` in any channel to declare your first incident.

## Upgrading

Each [release](https://github.com/FireFightLabs/firefight/releases) carries its own notes. Read them before upgrading, since some releases need a migration you should know about.

```sh
docker compose pull firefight
docker compose up -d firefight
```

Migrations run on boot, so there is no separate step. Pin a version instead of `latest` if you would rather choose when that happens: set `image: ghcr.io/firefightlabs/firefight:v1.2.3` in `docker-compose.yml`.

## Backing up

Everything lives in Postgres apart from uploaded files.

```sh
docker compose exec postgres pg_dumpall -U firefight > firefight-$(date +%F).sql
```

The `storage` volume holds uploads. Back that up too if your team attaches files to incidents.

Restoring a backup without the Active Record encryption keys from step 2 gives you a database you cannot read. Store them with the backups, not only on the machine.

## Running it another way

The compose file is one arrangement, not a requirement. If you already have Postgres, a reverse proxy, or an orchestrator, the container needs:

| | |
|---|---|
| **Image** | `ghcr.io/firefightlabs/firefight:latest`, listening on port 80 |
| **Postgres** | 18 or newer, and four databases. Point `FIREFIGHT_DATABASE`, `_CACHE`, `_QUEUE` and `_CABLE` at them |
| **TLS** | Terminate it in front. Firefight sets `force_ssl`, so it redirects plain HTTP and expects the proxy to pass `X-Forwarded-Proto` |
| **Jobs** | Either set `SOLID_QUEUE_IN_PUMA=1` to run the worker inside the web process, or run a second container with `bin/jobs` |
| **Migrations** | `RUN_DB_PREPARE=true` migrates on boot, which is right for one container and wrong for several. With more than one web container, run `bin/rails db:prepare` as a separate step and leave the flag unset |
| **Hosts** | `ALLOWED_HOSTS` is required and has no default. The app will not boot without it |

`FIREFIGHT_DATABASE_SSLMODE` defaults to `require`. A managed Postgres will be fine with that. One on your own private network usually is not, so set it to `disable` there.

Every variable Firefight reads is listed in [`.env.example`](.env.example).

## When something is wrong

**The page will not load and Caddy logs a certificate error.** The DNS record is not pointing at the machine yet, or port 80 is closed. Let's Encrypt has to reach it to issue.

**Slack says `dispatch_failed` on a slash command.** The URLs in the manifest still point somewhere else, or Firefight is not reachable over HTTPS from the internet.

**Firefight starts and immediately exits.** Check the logs for a missing variable. `ALLOWED_HOSTS`, `SECRET_KEY_BASE` and the three encryption keys are all required, and the app refuses to boot rather than starting in a broken state.

**Everything works but nothing happens in the background.** No postmortems generate, no summaries appear, no webhooks deliver. The job worker is not running, so set `SOLID_QUEUE_IN_PUMA=1`.

**The database connection is refused with an SSL error.** Set `FIREFIGHT_DATABASE_SSLMODE=disable` if your Postgres is not serving TLS.

## Getting help

Ask in the [community Slack](https://firefight.app/slack), or open an [issue](https://github.com/FireFightLabs/firefight/issues) if you think you have found a bug. For anything security related, see [SECURITY.md](SECURITY.md) and report it privately.
