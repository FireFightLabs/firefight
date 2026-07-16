<h1 align="center">
  Firefight
</h1>
<p align="center">
  <b>Open-source, AI-first incident management.</b><br />
  Declare, coordinate, and resolve incidents from Slack, with AI that writes your catchups and postmortems, an audit-grade timeline, and a web dashboard for everything in between.
</p>

<h4 align="center">
  <a href="https://firefight.app">Website</a> ·
  <a href="#self-hosting">Self-hosting</a> ·
  <a href="#local-development">Local development</a> ·
  <a href="https://github.com/FireFightLabs/firefight/releases">Releases</a>
</h4>

<h4 align="center">
  <a href="https://github.com/FireFightLabs/firefight/blob/main/LICENSE">
    <img src="https://img.shields.io/badge/license-AGPL--3.0-blue" alt="Firefight is released under the AGPL-3.0 license" />
  </a>
  <a href="https://github.com/FireFightLabs/firefight/actions/workflows/ci.yml">
    <img src="https://github.com/FireFightLabs/firefight/actions/workflows/ci.yml/badge.svg" alt="CI status" />
  </a>
  <a href="https://github.com/FireFightLabs/firefight/blob/main/CONTRIBUTING.md">
    <img src="https://img.shields.io/badge/PRs-welcome-brightgreen" alt="PRs welcome" />
  </a>
  <a href="https://firefight.app/slack">
    <img src="https://img.shields.io/badge/chat-on%20Slack-blueviolet" alt="Chat with the Firefight community on Slack" />
  </a>
  <a href="https://x.com/FireFight_app">
    <img src="https://img.shields.io/twitter/follow/FireFight_app?label=Follow" alt="Follow Firefight on X" />
  </a>
</h4>

<p align="center">
  <img src=".github/assets/readme-hero.png" width="100%" alt="Firefight: declare and resolve incidents in Slack, tracked in a full web dashboard" />
</p>

## What is Firefight?

Firefight is an incident management platform built for the way teams actually respond: in Slack, under pressure, at 3am. Declare an incident with a slash command and Firefight creates the channel, posts the announcement, assigns the lead, tracks every status change, and keeps stakeholders updated, then generates the postmortem when it's over.

Everything that happens is recorded as an immutable, audit-grade event timeline, visible in a clean web dashboard alongside your service catalog, custom fields, and API keys.

## Features

### Incident response
- **Slack-native flow**: declare, update status and severity, assign a lead, invite responders, escalate, and close without leaving Slack
- **Incident channels**: created automatically with pinned quick actions, topic metadata, and announcement threads
- **Audit-grade timeline**: every state change is an immutable event with full attribution
- **Custom fields and incident types**: model your organization's process, not ours
- **Incident relationships**: link related and duplicate incidents

### AI built in
- **AI postmortems**: a structured draft generated from the incident's full timeline and channel transcript, ready for human editing
- **AI catchups**: joining an incident late? Get a summary of what's happened so far
- **Cost-tracked inference**: every AI call is logged with tokens, latency, and cost

### Platform
- **Web dashboard**: incident list with server-side filtering, incident detail with timeline, postmortem editor, settings
- **Alert ingestion and routing**: point your monitoring at a per-source endpoint, then route with first-match-wins rules that open an incident, attach to an open one, notify a team, or drop it, with deduplication, flap handling, and storm grouping so an alert storm becomes one incident
- **Service catalog**: services, teams, environments, and functionality with typed attributes and relationships
- **REST API**: incident CRUD with bearer-token auth, granular per-key permissions, and idempotency keys
- **Outbound webhooks**: subscribe external systems to incident events, with delivery tracking and retries
- **Workflow engine**: durable, step-based orchestration with retries, crash recovery, and a full execution audit trail

### On the roadmap
- First-class alert adapters for Datadog, PagerDuty, and Grafana (any tool that can POST JSON works today through the generic webhook adapter)
- AI SRE investigator: autonomous, permission-gated incident investigation with evidence-backed findings
- On-call scheduling and escalation policies
- Microsoft Teams support

## Getting started

| | |
|---|---|
| **Firefight Cloud** | The fastest way to get started: managed hosting with AI features included. Coming soon at [firefight.app](https://firefight.app). |
| **Self-hosting** | Run Firefight on your own infrastructure. See [Self-hosting](#self-hosting) below. |

## Self-hosting

Firefight ships as a Docker image with every release:

```sh
docker pull ghcr.io/firefightlabs/firefight:latest
```

You'll need PostgreSQL 18+, a Slack app, and the environment variables documented in [`.env.example`](.env.example). Each [release](https://github.com/FireFightLabs/firefight/releases) includes upgrade notes; upgrading is `docker pull` plus `bin/rails db:prepare`.

## Local development

```sh
mise install                          # Ruby + Node toolchain
docker run -d --name firefight-postgres -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=postgres -p 5432:5432 \
  -v firefight-postgres-data:/var/lib/postgresql postgres:18.3
bundle install
bin/rails db:prepare && bin/rails db:prepare RAILS_ENV=test
bin/dev
```

Full setup (Slack app creation, environment variables, the local tunnel for Slack callbacks, and how the multi-database layout works) is in [CONTRIBUTING.md](CONTRIBUTING.md).

## Open source vs. paid

This repository is licensed under [AGPL-3.0](LICENSE): free to use, self-host, and modify; if you run a modified version as a service, you must share your changes under the same license.

Firefight Cloud is our managed offering: hosting, upgrades, and AI features with usage included in the plan. Self-hosters bring their own LLM API key for the AI features.

## Security

Found a vulnerability? Please report it privately; see [SECURITY.md](SECURITY.md). Do not open a public issue for security problems.

## Contributing

Contributions are welcome: bug reports, fixes, and features. Start with [CONTRIBUTING.md](CONTRIBUTING.md) for the development setup and conventions. Fork PRs run the full CI suite, no secrets required.

## License

[AGPL-3.0](LICENSE) © Firefight Labs
