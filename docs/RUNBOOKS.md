# Runbooks — Feature Story

## Context

Incident responders repeat the same recovery steps over and over. When Postgres falls over at 3 AM, the person on-call shouldn't be grepping through Slack history or Notion to find what to do. Runbooks solve this — short, step-by-step procedures that tell you exactly how to handle a specific failure.

Firefight is an incident management platform without runbook support today. Customers coordinate in channels, record timelines, run post-mortems — but the actual "what to do next" lives outside the product. That's a gap worth closing before we push hard on enterprise.

## Vocabulary

- **Runbook** — "how to fix X." Tactical, step-by-step instructions for a specific technical problem. Example: "Postgres primary fell over — here's the 6-step failover procedure."
- **Playbook** — "how we respond to any incident." Strategic, covers who does what, communication channels, escalation rules. Owned by incident commanders and leadership.

This story is about **runbooks**. Playbooks are a larger, later initiative that maps more closely to incident.io's full workflow engine.

## Why now

1. **Launch table-stakes.** Competitors (incident.io, Rootly, FireHydrant) all have runbook support. Without it, enterprise prospects ask "how do we document our standard recoveries?" and the answer is "we don't" — loss of deal.
2. **Leverages existing infra.** We already have incident types, custom fields, a workflow engine (SolidWorkflow), and Slack integration. Runbooks plug into these, not compete with them.
3. **AI angle.** An AI assistant that suggests the right runbook for an active incident is a differentiator. Hard to build without the content layer first.

## Product goals

1. **Document once, reuse forever.** Teams write runbooks in Firefight, not in a separate wiki.
2. **Attach to incidents automatically.** When an incident matches conditions (type, severity, service, alert source), the relevant runbook is posted in the channel.
3. **Track execution.** Each step can be marked complete by a responder, creating an audit trail in the incident timeline.
4. **Keep it simple.** MVP is markdown + ordered steps + conditional attachment. No branching logic, no nested runbooks, no scripting.

## Approach (inspired by incident.io)

Incident.io separates runbooks (content) from workflows (automation). We do the same:

- **Runbooks** are content: title, description, markdown steps.
- **Workflow triggers** (already in our codebase via SolidWorkflow) auto-attach runbooks when conditions match.
- **Timeline integration** records when a runbook was attached, which steps were completed, and by whom — same event model as `IncidentEvent`.

## Scope — MVP

### In scope

- Runbook CRUD (dashboard + API)
- Markdown body with optional ordered steps (checkbox list)
- Scoping: attach runbooks to specific incident types, severities, or services (catalog entries)
- Auto-attach to matching incidents on creation — post summary + link in Slack channel
- Manual attach from incident page (search + select)
- Mark step complete — records an `IncidentEvent`, visible in timeline
- Audit log of who attached and who completed each step

### Out of scope (future)

- Conditional branching ("if X, do step 3, else do step 4")
- Embedded actions (run this command, call this API)
- Versioning / draft vs published
- AI-suggested runbook based on incident description
- Imports from Notion/Confluence
- Nested runbooks (runbook that references other runbooks)

## Data model (rough sketch)

```
runbooks
  id, workspace_id, title, slug, summary, content (markdown),
  created_by_id (workspace_membership), created_at, updated_at

runbook_steps
  id, runbook_id, order, title, body, created_at, updated_at

runbook_triggers
  id, runbook_id, condition_type (incident_type | severity | service | catalog_entry),
  condition_value, created_at

incident_runbooks
  id, incident_id, runbook_id, attached_at, attached_by_id, attached_automatically (bool)

incident_runbook_step_completions
  id, incident_runbook_id, runbook_step_id, completed_at, completed_by_id
```

Reuse `IncidentEvent` for timeline entries — add event types like `runbook.attached`, `runbook.step.completed`.

## First runbooks we'll ship as templates

Launch with a small library of templates customers can fork into their workspace. Covers common SaaS failure modes:

- **Database primary down** — failover to replica, promote, update connection strings
- **Service degraded — elevated error rate** — rollback, check recent deploys, scale up
- **Certificate expired** — renewal and deployment procedure
- **Secret leaked** — rotate, redeploy, revoke, notify affected parties
- **Deploy rollback** — how to revert the last release safely
- **Full region outage** — traffic failover to DR region

Templates ship as seed data; customers duplicate and edit.

## Success metrics

- % of incidents with at least one runbook attached (target: 30% within 3 months of launch)
- Median time from incident declared → first runbook attached (target: < 2 minutes via auto-attach)
- Step completion rate within incident duration (target: 50%+ of attached steps marked done)

## Open questions

- Should runbooks live under Catalogue (as a new type) or be their own top-level resource? Leaning top-level — catalogues are for service inventory, runbooks are procedures.
- Do we version runbook content? MVP says no, but if a runbook changes mid-incident, the timeline should show which version was followed. Defer but note the risk.
- Should step completion be restricted to the incident lead or open to any channel member? MVP: any member, keep it collaborative.

## References

- [incident.io — What are runbooks?](https://incident.io/blog/what-are-runbooks)
- [Rootly — Runbooks in incident response](https://rootly.com/incident-response/runbooks)
