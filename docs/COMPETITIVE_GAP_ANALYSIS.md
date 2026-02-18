# Competitive Gap Analysis: Firefight vs Rootly & incident.io

## Context

Firefight is pre-release. This analysis compares core incident management features (not postmortems, integrations, or analytics dashboards) against Rootly and incident.io to identify missing functionality and flexibility gaps.

## What Firefight Already Has

Incident creation (modal), statuses (live/closed categories), severities (ranked), incident lead role, close/resolve/reopen flows, status/severity updates, summary updates, actions & followups, events/timeline (stored but no viewer), sequential numbering, quick actions message, announcement to #incidents, auto channel creation (public/private), channel topic updates, lead assignment (self-assign + modal), next update reminders, workflow engine, private incidents.

---

## Missing Features (Core Incident Management)

### Incident Creation & Declaration

- **Create from Slack message** — hover on any message, "Create incident" action; pre-fills context link (both competitors)
- **API-based creation** — create incidents programmatically from monitoring tools, CI/CD, external services (both)
- **Zero-friction creation** — create incident with no fields filled, auto-generate name (incident.io)
- **Convert existing channel** — `/ff convert` turns existing Slack channel into incident channel preserving history (Rootly)
- **Retrospective incidents** — declare incidents after the fact, skip announcements, mark as retrospective in reporting (incident.io)
- **Test/training incidents** — create test incidents that don't pollute metrics or broadcast publicly (both)

### Statuses & Lifecycle

- **Triage stage** — incidents from alerts start in triage; can be accepted, declined, or merged before going "live" (both)
- **Custom lifecycle per incident type** — different status flows for different incident types (e.g., Engineering vs Security) (incident.io)
- **Cancellation status** — for false positives or duplicates, separate from "resolved" (Rootly)
- **Sub-statuses with forms** — each status transition has a customizable form for data collection (Rootly)
- **Configurable status progression rules** — enforce sequential progression, allow/disallow backward movement (Rootly)
- **Timestamps per status** — auto-record when each status was first entered, not just declared_at and resolved_at (both)

### Roles & Assignment

- **Multiple custom roles** — beyond just "Lead"; e.g., Communications Lead, Data Protection Officer (both)
- **Multi-user per role** — allow multiple people assigned to the same role (Rootly)
- **Per-role responsibilities message** — configurable message sent when someone is assigned a role (Rootly)
- **Per-incident-type roles** — different roles appear for different incident types (incident.io)
- **Conditional role requirements** — e.g., Comms Lead required only when severity is Critical (incident.io)
- **Team-based auto-assignment** — when a team is attached, auto-assign configured roles to team members (Rootly)
- **On-call schedule-based auto-assignment** — auto-assign roles based on who is currently on-call (both)

### Severity

- **Severity descriptions** — per-severity explanation of what each level means (both)
- **Per-type severity descriptions** — same severity levels but different descriptions per incident type (incident.io)

### Communication & Channels

- **Channel bookmarks** — configurable bookmarks bar at top of incident channel (runbook links, video call, severity badge) (both)
- **Conditional bookmarks** — auto-added when conditions become true (e.g., critical incident doc only for Critical) (incident.io)
- **Auto-generated video call** — create Zoom/Meet/Teams meeting URL automatically per incident (incident.io)
- **Channel archival on close** — auto-archive incident channels after resolution (Rootly)
- **Configurable announcement rules** — choose which channels get announcements based on severity, type, etc. (incident.io)
- **Inactivity reminders** — auto-remind when incident channel goes quiet (Rootly)

### Incident Updates

- **Scheduled update cadence** — "When will you next update?" with system reminder when due (incident.io; Firefight has `next_update_at` but only as a field, not a proper cadence system)
- **AI-suggested summaries** — auto-generate summary suggestions as incident progresses (both)
- **Announcement thread updates** — post updates in the #incidents channel as threaded replies (Firefight has this for status changes but not for general updates)

### Escalation

- **Escalation from incident channel** — page on-call responders, teams, or escalation policies (both)
- **Escalation context** — provide reason/context when paging someone (both)
- **Escalation policies** — step-based escalation if not acknowledged (both)
- **Smart escalation paths** — route based on priority, working hours, impacted service (incident.io)

### Actions & Follow-ups

- **Priority on actions/followups** — High/Medium/Low priority levels (both; Firefight has none)
- **Due dates on followups** — accountability with due dates (both)
- **Action reminders** — configurable reminders for overdue actions (Rootly)
- **Create from message reaction** — emoji reaction on a Slack message creates an action (incident.io has boom emoji; Firefight has the handler infrastructure but unclear if fully wired)
- **External tracker sync** — export followups to Jira, Linear, GitHub with bidirectional sync (both)
- **Default tasks per role** — auto-create tasks when someone is assigned a role (Rootly)

### Incident Types / Templates

- **Incident types** — classify incidents by nature (Production, Security, Customer, etc.) (both)
- **Per-type configuration** — each type gets its own lifecycle, roles, fields, forms, workflows (both)
- **Dynamic creation forms** — form changes based on selected type (both)

### Custom Fields

- **Active custom fields system** — Firefight has the JSONB column but no UI/handlers to manage custom fields (both competitors have full field type systems: text, select, multi-select, number, date, checkbox, link)
- **Catalog-backed fields** — fields backed by service/team catalogs (incident.io)
- **Conditional field visibility** — show/hide fields based on other field values (both)
- **Conditional field requirements** — required only under certain conditions (incident.io)

### Services & Infrastructure Catalog

- **Service catalog** — map services, teams, environments, functionalities; attach to incidents (both)
- **Service ownership** — each service has an owning team; drives auto-assignment and escalation (both)
- **Affected services field** — track which services are impacted (both)
- **Environments** — track affected environments (production, staging, etc.) (Rootly)

### Timeline & Visibility

- **Timeline viewer** — `/ff timeline` command to view incident timeline (Firefight stores events but has no viewer)
- **Pin messages to timeline** — pin or react to Slack messages to add them to the timeline (incident.io)
- **Custom timeline events** — add events that happened outside the channel with custom timestamps (incident.io)
- **Star/highlight events** — mark major milestones in the timeline (Rootly)
- **Internal vs external events** — control which timeline events appear on public-facing pages (Rootly)
- **Timeline export** — download for retrospectives/compliance (Rootly)

### Subscribers & Stakeholders

- **Subscriber system** — users subscribe to specific incidents; get DM/email notifications on updates (both)
- **Auto-subscribe rules** — "subscribe me to all Critical incidents" or "incidents affecting my team" (incident.io)
- **Notification channels** — Slack DM, email, SMS options for subscriber notifications (both)
- **Internal status page** — stakeholder-facing view of active incidents (both)

### Advanced Incident Operations

- **Incident pausing** — pause incident with auto-resume; paused time excluded from metrics (incident.io)
- **Incident merging** — merge duplicate incidents together (incident.io)
- **Related incidents** — AI-powered detection of similar past incidents (incident.io)
- **Sub-incidents** — parent-child relationships with separate channels (Rootly)
- **Incident streams** — sub-workstreams within a single incident, each with own channel and lead (incident.io)
- **Duplicate marking** — mark incident as duplicate of another (Rootly)
- **Maintenance/scheduled incidents** — separate lifecycle for planned maintenance windows (Rootly)

### Workflow & Automation

- **Workflow triggers beyond lifecycle** — trigger on field changes, role assignments, team/service changes, user joins/leaves, custom field updates (both)
- **Workflow conditions** — filter by severity, type, service, team, custom fields (both)
- **Decision flows** — interactive question-answer runbooks triggered by keywords or incident properties (incident.io)
- **Liquid/template variables** — dynamic content in all workflow actions using incident variables (Rootly)
- **Alert-to-incident automation** — auto-create incidents from monitoring tool alerts (both)

### Platform & Access

- **Web dashboard** — view, manage, and declare incidents from a web UI (both)
- **Microsoft Teams support** — full incident management in Teams (both)
- **Mobile app** — iOS/Android with push notifications (both)
- **RBAC / permissions** — granular user permissions beyond workspace membership (both)
- **Incident feedback** — responder satisfaction/feedback collection after incidents (Rootly)

---

## Priority Tiers (Suggested)

**Tier 1 — Table stakes for launch:**
- Incident types/templates
- Active custom fields
- Timeline viewer (`/ff timeline`)
- Escalation (page on-call)
- Web dashboard (at minimum: list incidents, view detail)

**Tier 2 — High value, expected by teams:**
- Service catalog (affected services)
- Multiple custom roles
- Subscriber/stakeholder notifications
- Create from Slack message action
- Channel bookmarks
- Triage status stage

**Tier 3 — Differentiators & power features:**
- Per-type lifecycle/forms/roles
- Decision flows / interactive runbooks
- Sub-incidents or streams
- AI-powered features
- Alert-to-incident automation
- Incident pausing / merging
- Microsoft Teams support
