# AI Action Tools

## Context

The AI (`IncidentResponder`) is currently read-only — it answers questions about incidents but can't take actions. This plan adds RubyLLM tool use so the AI can automate existing Firefight capabilities: change severity, assign lead, create actions, update status, etc.

This is Layer 1 of the product roadmap. It establishes the tool infrastructure that all future AI capabilities (including AI SRE log/metrics tools) will use.

## Product Roadmap

### Phase A: Foundation (build before AI SRE)

1. **AI action tools** (this plan) — AI automates existing Firefight capabilities via RubyLLM tool use
2. **Webhooks** — Inbound webhook endpoints for external systems to push alerts/events
3. **REST API** — API endpoints for incidents, exposing Firefight data outward
4. **Service catalog** — Service model with ownership, dependencies, metadata
5. **Trigger incidents from external sources** — Alert from Datadog/Sentry/etc. auto-creates incident + pages on-call

### Phase B: AI SRE (after foundation is solid)

1. Investigate root cause (auto-investigation on incident creation)
2. Code indexing / code intelligence (GitHub/GitLab integration)
3. Metrics pulling (Datadog, Grafana, Railway logs)
4. AI fixing code automatically (draft PRs, rollbacks)

### Out of scope

- HR Systems (BambooHR, Personio)
- Everything Else (Statuspage, Salesforce, Okta, Zapier)

### Integration categories (incident.io reference)

| Category | What it covers | Our phase |
|----------|---------------|-----------|
| Issue Tracking | Jira, Linear, GitHub Issues — sync action items as tickets | Phase A |
| Service Catalog | Backstage, Cortex — import service definitions | Phase A |
| Alerts and Paging | Datadog, Sentry, PagerDuty (29 sources) — receive alerts, create incidents | Phase A |
| Video and Documents | Zoom, Google Meet, Confluence — auto-start calls, export postmortems | Later |
| HR Systems | BambooHR, Personio — time-off calendars for on-call | Out of scope |
| Everything Else | Statuspage, Salesforce, Okta, Zapier | Out of scope |

## Architecture

```
User: "@Firefight escalate to critical and assign Alice as lead"
  |
  v
AppMentionHandler --> IncidentResponseJob (passes user context)
  |
  v
IncidentResponder.answer_question(incident, question:, asked_by:)
  |
  v
RubyLLM chat.with_tools(UpdateSeverity, AssignLead, CreateAction, ...)
  |
  v
LLM decides to call tools --> RubyLLM executes --> feeds result back --> LLM responds
  |
  v
"Done. Escalated to Critical and assigned Alice as lead."
```

Each tool wraps existing business logic (services, model updates, workflows). Tools are thin — they validate params, call existing code, return a confirmation string.

## Implementation

### Step 1: Pass requesting user through the chain

Currently `IncidentResponseJob` doesn't know WHO asked the question. Tools need this for audit trail (`record_change!(user: member)`).

**Modify `app/services/events/app_mention_handler.rb`:**

Pass the user who mentioned @Firefight:

```ruby
# Current:
FirefightAi::IncidentResponseJob.perform_later(incident.id, channel_id, event["ts"], user_text)

# New:
FirefightAi::IncidentResponseJob.perform_later(incident.id, channel_id, event["ts"], user_text, event["user"])
```

**Modify `app/services/commands/firefight/catchup_handler.rb`:**

```ruby
# Current:
FirefightAi::IncidentResponseJob.perform_later(command.incident.id, command.channel_id, nil, CATCHUP_QUESTION)

# New:
FirefightAi::IncidentResponseJob.perform_later(command.incident.id, command.channel_id, nil, CATCHUP_QUESTION, command.user_id)
```

**Modify `engines/firefight_ai/app/jobs/firefight_ai/incident_response_job.rb`:**

```ruby
def perform(incident_id, channel_id, thread_ts, question, platform_user_id = nil)
  incident = Incident.find(incident_id)
  member = resolve_member(incident.workspace, platform_user_id)
  responder = IncidentResponder.new(incident.workspace)
  answer = responder.answer_question(incident, question: question, asked_by: member)
  # ... post response
end

private

def resolve_member(workspace, platform_user_id)
  return nil unless platform_user_id
  workspace.workspace_memberships.find_by(platform_user_id: platform_user_id)
end
```

### Step 2: Tool infrastructure in IncidentResponder

**Modify `engines/firefight_ai/app/services/firefight_ai/incident_responder.rb`:**

```ruby
def answer_question(incident, question:, asked_by: nil)
  @incident = incident
  @asked_by = asked_by
  context = incident.to_full_context
  call_ai(context, question)
end

def call_ai(context, question)
  chat = RubyLLM.chat(model: ai_model)
  chat.with_instructions(system_prompt)
  tools = available_tools
  chat.with_tools(*tools) if tools.any?
  response = chat.ask(user_prompt(context, question))
  response.content
end

def available_tools
  return [] unless @asked_by

  [
    Tools::UpdateSeverity.new(@incident, @asked_by),
    Tools::UpdateStatus.new(@incident, @asked_by),
    Tools::AssignLead.new(@incident, @asked_by),
    Tools::UpdateSummary.new(@incident, @asked_by),
    Tools::CreateAction.new(@incident, @asked_by),
    Tools::CreateFollowup.new(@incident, @asked_by)
  ]
end
```

Tools only registered when we know who asked (for audit trail). No tools = read-only mode (backwards compatible).

Update system prompt to mention action capabilities when tools are available.

### Step 3: Action tools

All tools in `engines/firefight_ai/app/tools/firefight_ai/tools/`. Each follows:

```ruby
class ToolName < RubyLLM::Tool
  description "..."
  param :param_name, type: "string", desc: "...", required: true

  def initialize(incident, asked_by)
    @incident = incident
    @asked_by = asked_by
    super()
  end

  def execute(param_name:)
    # validate, call existing service/model code, return confirmation string
  rescue => e
    "Failed: #{e.message}"
  end
end
```

#### Tool 1: UpdateSeverity

```ruby
description "Change the severity of the current incident"
param :severity_name, type: "string", desc: "Severity name (e.g., 'Critical', 'Major', 'Minor')", required: true
```

- Find severity: `@incident.workspace.incident_severities.find_by!(name: severity_name)`
- Update: `@incident.update!(incident_severity: severity)`
- Record event: `@incident.record_change!(user: @asked_by, event_type: IncidentEvent::INCIDENT_UPDATED)`
- Start workflow: `IncidentUpdateWorkflow.start!(@incident, context: { changed_by_id: @asked_by.id })`

Reuses: `Incident::Snapshots#record_change!`, `IncidentUpdateWorkflow`

#### Tool 2: UpdateStatus

```ruby
description "Change the status of the current incident"
param :status_name, type: "string", desc: "Status name (e.g., 'Triage', 'Investigating', 'Monitoring', 'Resolved')", required: true
```

- Find status: `@incident.workspace.incident_statuses.find_by!(name: status_name)`
- Guard: if resolving, set `resolved_at`; if reopening from resolved, clear `resolved_at`
- Update + record event + start appropriate workflow (update/close/reopen)

Reuses: `Incident::Lifecycle`, existing workflows

#### Tool 3: AssignLead

```ruby
description "Assign an incident lead by name"
param :user_name, type: "string", desc: "Name of the person to assign as lead", required: true
```

- Find member by name: `@incident.workspace.workspace_memberships.joins(:user).find_by!(users: { name: user_name })`
- Assign lead role via `IncidentRoleAssignment`
- Record event: `LEAD_ASSIGNED`
- Start workflow: `LeadAssignmentWorkflow.start!`

Reuses: `Incident::RoleManagement#lead`, `LeadAssignmentWorkflow`

#### Tool 4: UpdateSummary

```ruby
description "Update the incident summary"
param :summary, type: "string", desc: "The new incident summary", required: true
```

- Update: `@incident.update!(summary: summary)`
- Record event: `INCIDENT_UPDATED`
- Start workflow: `SummaryUpdateWorkflow.start!`

Reuses: `SummaryUpdateWorkflow`

#### Tool 5: CreateAction

```ruby
description "Create an action item for the incident"
param :description, type: "string", desc: "What needs to be done", required: true
param :assignee_name, type: "string", desc: "Name of person to assign (optional)", required: false
```

- Resolve assignee by name (if provided)
- Call: `IncidentActionService.create_action(@incident, description:, action_type: ACTION_TYPE_ACTION, created_by: @asked_by, assignee:)`

Reuses: `IncidentActionService#create_action`

#### Tool 6: CreateFollowup

Same as CreateAction but with `action_type: ACTION_TYPE_FOLLOWUP`.

Reuses: `IncidentActionService#create_action`

## Files

### Create

| File | Purpose |
|------|---------|
| `engines/firefight_ai/app/tools/firefight_ai/tools/update_severity.rb` | Change severity |
| `engines/firefight_ai/app/tools/firefight_ai/tools/update_status.rb` | Change status |
| `engines/firefight_ai/app/tools/firefight_ai/tools/assign_lead.rb` | Assign lead |
| `engines/firefight_ai/app/tools/firefight_ai/tools/update_summary.rb` | Update summary |
| `engines/firefight_ai/app/tools/firefight_ai/tools/create_action.rb` | Create action item |
| `engines/firefight_ai/app/tools/firefight_ai/tools/create_followup.rb` | Create follow-up |
| `engines/firefight_ai/test/tools/firefight_ai/tools/update_severity_test.rb` | Tool test |
| `engines/firefight_ai/test/tools/firefight_ai/tools/update_status_test.rb` | Tool test |
| `engines/firefight_ai/test/tools/firefight_ai/tools/assign_lead_test.rb` | Tool test |
| `engines/firefight_ai/test/tools/firefight_ai/tools/update_summary_test.rb` | Tool test |
| `engines/firefight_ai/test/tools/firefight_ai/tools/create_action_test.rb` | Tool test |
| `engines/firefight_ai/test/tools/firefight_ai/tools/create_followup_test.rb` | Tool test |

### Modify

| File | Change |
|------|--------|
| `app/services/events/app_mention_handler.rb` | Pass `event["user"]` to job |
| `app/services/commands/firefight/catchup_handler.rb` | Pass `command.user_id` to job |
| `engines/firefight_ai/app/jobs/firefight_ai/incident_response_job.rb` | Accept + resolve `platform_user_id` |
| `engines/firefight_ai/app/services/firefight_ai/incident_responder.rb` | Add `asked_by:`, `available_tools`, `with_tools` |
| `engines/firefight_ai/test/services/firefight_ai/incident_responder_test.rb` | Add tool integration tests |
| `test/services/events/app_mention_handler_test.rb` | Update for new job args |
| `test/services/commands/firefight/catchup_handler_test.rb` | Update for new job args |

### Key files to reuse

```
app/models/concerns/incident/snapshots.rb       -- record_change! for event recording
app/models/concerns/incident/lifecycle.rb        -- status transition logic
app/models/concerns/incident/role_management.rb  -- lead assignment
app/services/incident_action_service.rb          -- create_action, pick_up, complete
app/workflows/incident_update_workflow.rb        -- post-update side effects
app/workflows/summary_update_workflow.rb         -- post-summary-update side effects
app/workflows/lead_assignment_workflow.rb         -- post-lead-assignment side effects
```

## Future action tools (not in this plan)

- `EscalateIncident` — escalate with reason
- `CloseIncident` — close/resolve incident
- `ReopenIncident` — reopen closed incident
- `InviteResponder` — invite someone to incident channel
- `LinkIncident` — link related incidents
- `CreateShoutout` — create a shoutout
- `PickUpAction` / `CompleteAction` — manage action items

## Future AI SRE tools (Phase B)

- `FetchLogs` — pull logs from infrastructure (Railway, Fly, Render) via `Integrations::LogAdapter.for(integration)`
- `FetchRecentDeploys` — pull recent PRs/commits from GitHub/GitLab
- `FetchMetrics` — pull error rates, latency from Datadog/Grafana
- `SearchCode` — search codebase for relevant files
- Auto-investigation on incident creation (proactive tool use)

## Verification

1. `bin/ci` passes
2. `@Firefight escalate this to critical` --> severity changes to Critical, event recorded, Slack messages updated
3. `@Firefight assign Alice as lead` --> lead assigned, workflow runs
4. `@Firefight create an action to check the database connection pool` --> action item created
5. `@Firefight what's going on and update the summary` --> AI answers the question AND updates the summary
6. `/ff catchup` still works with new job signature (backwards compatible via default param)
