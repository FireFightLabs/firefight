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

Halon reads a repository in a sandbox of its own, one per investigation or conversation, holding the repository's whole history and no credential. It starts from `ghcr.io/firefightlabs/firefight-sandbox` at the same version as the app. An app image that is not a release, such as one you built yourself, uses the `edge` build of the sandbox instead. Set `SANDBOX_IMAGE` to choose another.

With the compose file, uncomment the three lines under the Halon comment and the socket mount, then set `DOCKER_GID` in `.env` to the group that owns the socket (`stat -c %g /var/run/docker.sock`). Mounting the socket gives Firefight control of your Docker daemon, which is why it is off by default. `firefight_default` is the network compose makes for this project, so check `docker network ls` if you named the project something else.

Boxes can reach the internet, so a repository's own tests can too. Running commands and tests is only offered to workspaces with Halon switched on.

The same box is Halon's terminal. Halon runs commands of its own there, such as a script over a large result or a check of an address from outside. A command reaches your connected tools only through Firefight, at the app's own address (`APP_HOST`, or `CODE_AGENT_PROXY_URL` when the boxes reach Firefight elsewhere), with a token that lasts as long as the command. With Docker boxes, set `SANDBOX_REGION` to say where they run, so a check from one says where it was seen from. Northflank and boat boxes say it themselves.

Every setting is described in [`.env.example`](.env.example).

### On Northflank

When Firefight itself runs on Northflank, each box can be a private service there instead. Keep the boxes in a project of their own, so they never share the app's secrets.

1. Create a project for the boxes in the same team and on the same cluster as the app's project. Northflank only lets projects talk to each other within one team and cluster.
2. Give that project no secret groups. A secret group reaches every service in its project, and a box must hold no credential.
3. In the boxes' project settings, under networking, allow ingress from the app's project. This is one-way, so the app reaches the boxes and the boxes cannot reach the app.
4. Create a Northflank API token whose role can read the boxes' project, create, read and delete its services, and read their runtime environment. The operator console needs that last one to adopt a box Firefight lost track of.
5. On the app, set `SANDBOX_PROVIDER=northflank`, `NORTHFLANK_API_TOKEN` to that token and `NORTHFLANK_SANDBOX_PROJECT` to the boxes' project id, then redeploy.

Firefight reads its own project from Northflank, so it knows the boxes are elsewhere and reaches them at the address Northflank gives other projects. If the boxes' project does not allow ingress from the app's project, code reading says the sandbox did not come up, or names the ingress setting when Northflank reports it, so check step 3 first. `NORTHFLANK_SANDBOX_PROJECT` can also be the app's own project, and then boxes are reached inside it.

### On boat.dev

Each box can be a [boat.dev](https://boat.dev) sandbox instead, a Linux VM in the EU billed by the second while it runs. Firefight starts the sandbox image inside it, so the box is the same as anywhere else, and the VM's Docker lets a repository's setup start the services its CI names from their own images, such as a pgvector or PostGIS Postgres. Firefight reaches the box at the https address boat.dev gives its port, which only answers with that address's token and the box's own key.

1. Create a boat.dev API key with the actions `sandbox.create`, `sandbox.read`, `sandbox.update`, `sandbox.stop`, `sandbox.delete`, `exec`, `host`, `snapshot.read` and `snapshot.write`.
2. Set `SANDBOX_PROVIDER=boat` and `BOAT_API_KEY` to that key. `BOAT_SANDBOX_TYPE` picks the size (`small`, `default`, `large` or `xlarge`, `default` unless set) and `BOAT_ORG` the organization that pays, when the key's account belongs to one.

Boxes are created with none of the account's own secrets. The first box of each sandbox version pulls the image and keeps a copy of itself under a name starting `halon-image-`, so later boxes start in seconds. A repository prepared from nothing, with its dependencies installed and its setup run, is kept as a named snapshot starting `halon-kept-`, per workspace and repository, and a later box for the same workspace starts from it. One nobody used for 7 days is removed. boat.dev keeps 10 named snapshots for free and charges for each above that. A stopped box is archived, then deleted an hour later.

### A backup provider

Set `SANDBOX_BACKUP_PROVIDER` to a second provider, and a box the first cannot start, for lack of capacity, an outage, a timeout or a refusal, starts there instead. The operator console lists each failover under Needs attention and on the workspace's page. A workspace can be held to one provider from its page in the operator console, under Workspaces, such as one whose data must stay in one region. Its boxes then run only there and never fail over.

## Signing in with Google or an email link

Slack sign-in works out of the box. Google and email links are optional and stay hidden until you turn them on.

1. For email links, set `SMTP_ADDRESS`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD` and `MAIL_FROM` in `.env`, with `APP_HOST` set to your dashboard's host. Firefight also emails a person whenever a new way to sign in is added to their account.
2. For Google, create an OAuth client of type Web application in Google Cloud with the redirect URI `https://<your-host>/auth/google_oauth2/callback`, and set `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET`.
3. `docker compose up -d`, then `docker compose exec web bin/rails 'feature_flags:enable_globally[self_serve_signup]'`.

With the flag on, someone who signs in and belongs to no workspace names a new one, and can connect Slack to it then or later from the banner on every page. Until Slack is connected, incidents cannot be declared. Admins invite teammates by email from Members, which needs the email settings above. Each person sees and removes their sign-in methods under Profile.

## Hearing about new workspaces

Set `INSTALL_NOTIFICATION_WEBHOOK_URL` to a Slack incoming webhook, or any URL that accepts a JSON POST, and Firefight posts one short message there for each of these:

- A workspace is created, however the person signed in: `New workspace: Acme, created by Ada Lovelace (ada@acme.com) with Google`. The method reads `Google`, `an email link` or `Slack`.
- A workspace that started without Slack connects it later: `Acme connected Slack (acme.slack.com)`.
- One of your AI accounts runs out of credit.

Besides `text`, the workspace messages carry `event` (`workspace.created` or `workspace.chat_connected`), `workspace_name`, `platform`, `platform_id`, `installer_name`, `installer_email`, `sign_up_method`, `created_at` and `installed_at`. A message that cannot be delivered is retried once and then logged, and never holds up the person signing up. Leave the variable unset and nothing is sent.

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
