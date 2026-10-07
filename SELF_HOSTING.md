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

Open [`config/slack_manifests/template.yml`](config/slack_manifests/template.yml) and replace every `<base-url>` with the address you will reach Firefight at, such as `https://firefight.example.com`. There are seven, covering the two slash commands, the events request URL, the interactivity request URL, and the two OAuth redirect URLs.

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

Faylee bug reports are optional and off by default. To enable them, set `FAYLEE_VERIFICATION_TOKEN` and `FAYLEE_SITE_ID` in `.env` with values from Faylee. The verification token is served at `/.well-known/faylee-verification.txt`, and the widget is added to every page inside a workspace when the site ID is set. Sign-in pages never load it.

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
| **Postgres** | 18 or newer with the `vector` extension available, and four databases. Point `FIREFIGHT_DATABASE`, `_CACHE`, `_QUEUE` and `_CABLE` at them. The compose file uses the `pgvector/pgvector` image, and managed Postgres on RDS, Supabase, Neon and PlanetScale all offer the extension |
| **TLS** | Terminate it in front. Firefight sets `force_ssl`, so it redirects plain HTTP and expects the proxy to pass `X-Forwarded-Proto` |
| **Jobs** | Either set `SOLID_QUEUE_IN_PUMA=1` to run the worker inside the web process, or run a second container with `bin/jobs` |
| **Migrations** | `RUN_DB_PREPARE=true` migrates on boot, which is right for one container and wrong for several. With more than one web container, run `bin/rails db:prepare` as a separate step and leave the flag unset |
| **Hosts** | `ALLOWED_HOSTS` is required and has no default. The app will not boot without it |

`FIREFIGHT_DATABASE_SSLMODE` defaults to `require`. A managed Postgres will be fine with that. One on your own private network usually is not, so set it to `disable` there.

Every variable Firefight reads is listed in [`.env.example`](.env.example).

## Letting Halon read code

Halon reads a repository in a sandbox of its own, one per investigation or conversation, holding the repository's whole history and no credential. It starts from `ghcr.io/firefightlabs/firefight-sandbox`, pulled by the same version as the app.

With the compose file, uncomment the three lines under the Halon comment and the socket mount, then set `DOCKER_GID` in `.env` to the group that owns the socket (`stat -c %g /var/run/docker.sock`). Mounting the socket gives Firefight control of your Docker daemon, which is why it is off by default. `firefight_default` is the network compose makes for this project, so check `docker network ls` if you named the project something else.

Boxes can reach the internet, so a repository's own tests can too. Running commands and tests is only offered to workspaces with Halon switched on.

Every setting is described in [`.env.example`](.env.example).

## Signing in with Google or an email link

Slack sign-in works out of the box. Google and email links are optional and stay hidden until you turn them on.

1. For email links, set `SMTP_ADDRESS`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD` and `MAIL_FROM` in `.env`, with `APP_HOST` set to your dashboard's host. Firefight also emails a person whenever a new way to sign in is added to their account.
2. For Google, create an OAuth client of type Web application in Google Cloud with the redirect URI `https://<your-host>/auth/google_oauth2/callback`, and set `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET`.
3. `docker compose up -d`, then `docker compose exec web bin/rails 'feature_flags:enable_globally[self_serve_signup]'`.

With the flag on, someone who signs in and belongs to no workspace names a new one, and can connect Slack to it then or later from the banner on every page. Until Slack is connected, incidents cannot be declared. Admins invite teammates by email from Members, which needs the email settings above. Each person sees and removes their sign-in methods under Profile.

## The operator console

`/operator` shows your install's background jobs: what is waiting, what failed and why, with retry. Only people you name can open it. Everyone else sees a not found page.

1. Sign in to Firefight once, then find your user id with `docker compose exec web bin/rails runner 'puts User.find_by(email: "you@example.com").id'`.
2. Add `OPERATOR_USER_IDS=<that id>` to `.env` (comma separated for more than one), then `docker compose up -d`.
3. Open `/operator`. The first time, scan the QR code with any authenticator app and save the recovery codes it shows. After that it asks for a code every 12 hours.

Lost your phone and your recovery codes: `docker compose exec web bin/rails 'operator:reset_authenticator[USER_ID]'`, then set it up again.

## When something is wrong

**The page will not load and Caddy logs a certificate error.** The DNS record is not pointing at the machine yet, or port 80 is closed. Let's Encrypt has to reach it to issue.

**Slack says `dispatch_failed` on a slash command.** The URLs in the manifest still point somewhere else, or Firefight is not reachable over HTTPS from the internet.

**Firefight starts and immediately exits.** Check the logs for a missing variable. `ALLOWED_HOSTS`, `SECRET_KEY_BASE` and the three encryption keys are all required, and the app refuses to boot rather than starting in a broken state.

**Everything works but nothing happens in the background.** No postmortems generate, no summaries appear, no webhooks deliver. The job worker is not running, so set `SOLID_QUEUE_IN_PUMA=1`.

**The database connection is refused with an SSL error.** Set `FIREFIGHT_DATABASE_SSLMODE=disable` if your Postgres is not serving TLS.

## Getting help

Ask in the [community Slack](https://firefight.app/slack), or open an [issue](https://github.com/FireFightLabs/firefight/issues) if you think you have found a bug. For anything security related, see [SECURITY.md](SECURITY.md) and report it privately.
