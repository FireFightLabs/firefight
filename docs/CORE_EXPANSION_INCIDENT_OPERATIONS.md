# Core Expansion: Incident Operations Platform

## Purpose

This document defines the product expansion after core incident management parity.

Goal: position Firefight as an **incident operating system** for SMBs/startups (teams of 2-30), not only an incident tracker.

## Product Thesis

After core workflow is solid, Firefight should win on one thing:

- Keep responders in the incident channel
- Bring diagnostics and operations into incident context
- Reduce tool switching during high-pressure moments

## Target Users

- Startup teams with lean ops capacity
- YC companies moving from ad-hoc to structured incident response
- SMB engineering orgs that need speed over enterprise process overhead

## Expansion Pillars

### 1) In-Channel Operational Actions (MCP-Powered)

Enable responders to run operational actions from the incident channel.

Examples:

- Restart service
- Roll back deploy
- Scale worker/web processes
- Clear queue / rerun job
- Trigger service health checks

Design requirements:

- Confirmations for risky actions
- Optional dual approval for high-risk production actions
- Full audit trail attached to incident timeline
- Permission model by workspace role + incident role

### 2) Service Context Card (Incident-Native Diagnostics)

Provide fast, incident-focused diagnostics without leaving Firefight.

Data slices:

- Error rate and latency trend (short windows: 15m/60m)
- Recent deploys and config changes
- Key service health signals
- Top failing endpoints/errors

Design principle:

- Do not replace observability tools
- Provide a high-signal "incident slice" optimized for triage and coordination

### 3) Dependency Health Watcher

Track critical external dependencies and map them into incident context.

Examples:

- Neon, Stripe, Cloudflare, Railway, etc.

Capabilities:

- Pull dependency status and degradation signals
- Link dependency events into incident timeline
- Flag probable external-cause incidents earlier

### 4) AI Operator Copilot (Actionable)

AI should be operational, not only summarization.

Primary job:

- Answer what changed and what is currently failing
- Suggest safe next actions
- Execute approved MCP actions via a controlled flow

Interaction pattern:

1. Query context (logs/metrics/deploy/dependencies)
2. Propose next step with confidence + risk
3. Human confirms
4. Action executes and is logged

### 5) Executable Runbook Snippets

Attach lightweight runbook steps that can be executed directly.

Capabilities:

- Markdown + executable steps
- Dry-run mode where supported
- One-click execute with approval checks
- Capture output into timeline event

### 6) Environment-Aware Safety Model

Support startup speed while protecting production.

Controls:

- Environment policy (prod/staging/dev)
- Risk tiering for actions
- Dual-approval for destructive production actions
- Break-glass flow with explicit reason logging

### 7) Auto-Briefing and Handoff Pack

Generate and maintain a live incident brief for async teams.

Sections:

- What we know
- What we do not know
- Current customer impact
- Last major changes
- Next top actions + owners

## Differentiation vs Enterprise Competitors

incident.io/Rootly/FireHydrant are strong at workflow orchestration.

Firefight differentiation should be:

- Faster operational execution from incident context
- Better startup ergonomics with fewer systems to coordinate
- Practical AI + MCP execution loop, not just status summarization

## MVP Scope (First Expansion Release)

### Must Have

1. MCP action framework with approvals, permissions, audit trail
2. Service context card (metrics + logs + deploy history summary)
3. Dependency watcher (status pull + timeline events)
4. AI copilot query/propose/execute flow for approved actions

### Should Have

5. Executable runbook snippets
6. Auto-brief handoff pack generation

### Later

7. Expanded connector catalog and deeper provider-specific actions
8. Proactive anomaly detection and recommendation tuning

## Suggested Connector Priorities

Prioritize tools common in startup stacks:

1. Railway / Render / Fly.io / Vercel (deploy/runtime control)
2. Neon / Supabase / managed Postgres providers
3. Datadog / Grafana / Sentry / New Relic (diagnostics input)
4. GitHub Actions / CI providers (rollback/redeploy hooks)

## Slack UX Direction

Use a simple command + modal/button model:

- `/ff ops` -> list safe contextual actions for this incident
- `/ff inspect` -> open service diagnostics snapshot
- `/ff deps` -> open dependency health panel
- `/ff copilot` -> ask/execute guided incident operations

All action executions should post structured timeline events:

- who initiated
- what was executed
- environment and target service
- result and output reference

## Non-Goals

- Full observability platform replacement
- Full SOAR/enterprise policy engine in initial phase
- Heavy, admin-first configuration burden

## Success Metrics

- Time-to-mitigation reduction for incidents using MCP actions
- Fewer context switches during active incidents
- Higher percentage of incidents with complete action audit trails
- Faster responder handoffs with auto-brief usage

## Delivery Sequence

1. MCP action framework + permissions + audit events
2. Service context card (read-only diagnostics)
3. Dependency watcher integrations
4. AI copilot query/propose/execute (limited actions)
5. Runbook snippets + auto-briefing

## Implementation Principle

Every expansion feature must strengthen core incident workflow, not distract from it.

If a feature does not improve responder decision speed, execution speed, or handoff quality during incidents, it is out of scope.
