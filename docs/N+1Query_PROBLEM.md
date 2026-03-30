# N+1 Query Investigation

This document captures likely N+1 query risks discovered during a read-only investigation of the codebase.

No code changes were made as part of this review.

## Summary

The most important suspected N+1 issues are in:

- API incident list rendering
- Dashboard page rendering
- Synchronous Slack command and modal flows

The biggest recurring root cause is repeated association access inside loops, especially through `Incident#lead`.

## Highest-Priority Likely N+1 Issues

### 1. API incidents index rendering

Files:

- `app/controllers/api/v1/incidents_controller.rb`
- `app/views/shared/_incident.json.jbuilder`
- `app/views/shared/_actor.json.jbuilder`
- `app/models/concerns/incident/role_management.rb`

Why this is likely:

- The index action includes `:incident_status, :incident_severity, :incident_type, :declared_by`
- The shared incident partial also accesses:
  - `incident.incident_status.incident_lifecycle_stage.key`
  - `incident.lead`
  - `incident.declared_by.user`
  - `incident.lead.user`
- `Incident#lead` is query-backed and not a simple preloaded association
- The partial calls `incident.lead` more than once

Criticality:

- High

Why it matters:

- Public API endpoint
- Supports paginated list rendering
- Likely to become noticeably slower with larger page sizes

Relevant references:

- `app/controllers/api/v1/incidents_controller.rb:7`
- `app/views/shared/_incident.json.jbuilder:20`
- `app/views/shared/_actor.json.jbuilder:2`
- `app/models/concerns/incident/role_management.rb:14`

### 2. Dashboard page render

Files:

- `app/controllers/dashboard_controller.rb`

Why this is likely:

- Dashboard incidents preload only `:incident_status, :incident_severity`
- During `incidents.map`, each incident also accesses:
  - `inc.incident_status.incident_lifecycle_stage.key`
  - `inc.incident_role_assignments.joins(:incident_role).find_by(...)`
  - `lead_assignment.workspace_membership.user.name`
- Those are loop-time lookups without corresponding eager loading

Criticality:

- High

Why it matters:

- User-facing Inertia page
- Loads up to 50 incidents synchronously
- Likely to create visible page-load delays

Relevant references:

- `app/controllers/dashboard_controller.rb:5`
- `app/controllers/dashboard_controller.rb:35`

### 3. Slack incident list command

Files:

- `app/services/commands/firefight/list_handler.rb`
- `app/adapters/slack/workspace_adapter/incident_messaging.rb`
- `app/models/concerns/incident/role_management.rb`

Why this is likely:

- Handler preloads only status and severity
- Formatter calls `incident.lead` twice per incident when rendering the line
- `incident.lead` performs DB work

Criticality:

- High

Why it matters:

- Synchronous Slack command path
- Slack expects fast responses
- Query amplification here can contribute to slow or failed interactive responses

Relevant references:

- `app/services/commands/firefight/list_handler.rb:13`
- `app/adapters/slack/workspace_adapter/incident_messaging.rb:102`
- `app/models/concerns/incident/role_management.rb:14`

### 4. Slack timeline modal

Files:

- `app/adapters/slack/workspace_adapter/incident_messaging.rb`
- `app/adapters/slack/incident_timeline_formatter.rb`

Why this is likely:

- Timeline builder loads events with `includes(:eventable)`
- Formatter also reads `event.user&.platform_user_id`
- `:user` is not eager loaded in the timeline query
- Timeline rendering iterates over all fetched events

Criticality:

- High

Why it matters:

- Synchronous Slack modal open/update path
- Event counts can grow quickly
- This can directly affect modal responsiveness

Relevant references:

- `app/adapters/slack/workspace_adapter/incident_messaging.rb:286`
- `app/adapters/slack/incident_timeline_formatter.rb:46`

### 5. Slack actions and follow-ups modal lists

Files:

- `app/adapters/slack/modal_builder.rb`

Why this is likely:

- Modal list builders load actions/followups
- Rendering later accesses `action.assignee.platform_user_id`
- No eager loading of `assignee` is visible in these collection queries

Criticality:

- Medium-high

Why it matters:

- Synchronous Slack modal path
- Can create one extra query per assigned action/follow-up

Relevant references:

- `app/adapters/slack/modal_builder.rb:548`
- `app/adapters/slack/modal_builder.rb:564`
- `app/adapters/slack/modal_builder.rb:1003`

## Medium-Priority Likely N+1 Issues

### 6. AI / full incident context serialization

Files:

- `app/models/concerns/incident/serialization.rb`
- `app/models/incident_event.rb`
- `app/models/incident_action.rb`
- `app/models/shoutout.rb`

Why this is likely:

- `to_full_context` includes timeline events with `includes(:user)`
- `IncidentEvent#to_context_hash` accesses `user&.user&.name`, so nested membership user loading may still fan out
- Actions call `assignee&.user&.name`
- Shoutouts call `from_member.user.name` and `to_member&.user&.name`
- Top-level context also accesses `declared_by.user.name` and `lead&.user&.name`

Criticality:

- Medium

Why it matters:

- Likely background/AI-oriented rather than a top synchronous request
- Still potentially expensive on large incidents

Relevant references:

- `app/models/concerns/incident/serialization.rb:19`
- `app/models/incident_event.rb:101`
- `app/models/incident_action.rb:41`
- `app/models/shoutout.rb:10`

### 7. Transcript cache grouped message name resolution

Files:

- `app/services/incident_transcript_cache.rb`

Why this is likely:

- Builds `members = workspace.workspace_memberships.index_by(&:platform_user_id)`
- Then reads `members[...]&.user&.name`
- If `user` is not eager loaded, member name resolution can fan out into repeated queries

Criticality:

- Medium-low

Why it matters:

- Less likely to block the main request path
- Still a wasteful association access pattern

Relevant references:

- `app/services/incident_transcript_cache.rb:37`

### 8. Slack postmortem action rendering

Files:

- `app/adapters/slack/incident_message_builder.rb`

Why this is likely:

- Postmortem blocks iterate `incident.incident_actions.active`
- Rendering accesses `action.assignee.platform_user_id`
- No eager loading of `assignee` is visible here

Criticality:

- Medium-low

Why it matters:

- Potential per-action extra queries
- Lower risk than synchronous command or modal flows if this is typically async-triggered

Relevant references:

- `app/adapters/slack/incident_message_builder.rb:754`
- `app/adapters/slack/incident_message_builder.rb:767`

## Cross-Cutting Root Cause

### `Incident#lead`

File:

- `app/models/concerns/incident/role_management.rb`

Concern:

- `lead` performs query work every call:
  - looks up the incident lead role on the workspace
  - then finds the role assignment on the incident
- It is not memoized
- It is frequently used inside collection rendering

Why this matters:

- It appears in API rendering, dashboard rendering, and Slack formatting
- This makes it one of the most likely amplifiers of N+1 behavior across the app

Relevant reference:

- `app/models/concerns/incident/role_management.rb:14`

## Critical Path Assessment

Most likely to cause user-visible latency or stuck/slow endpoints:

1. API incidents index
2. Dashboard page render
3. Slack `/ff list`
4. Slack timeline modal open/update
5. Slack actions/follow-ups modals

These are important because they are synchronous request/interaction paths.

## Areas That Seem Fine or Lower Risk

### Probably fine

- `app/controllers/api/v1/statuses_controller.rb`
  - Includes `:incident_lifecycle_stage` and uses it directly
- `app/controllers/incidents_controller.rb`
  - No collection-heavy association loading visible
- `app/controllers/settings_controller.rb`
  - No collection-heavy association loading visible
- `app/controllers/catalogue_controller.rb`
  - No obvious N+1 pattern in current implementation

## Notes

- This investigation is based on static code analysis, not query-log measurement
- Some items are highly likely N+1s, while others are strong suspects based on association access patterns
- The most important next validation step would be to confirm these paths with logs, Bullet, or request-level query profiling
