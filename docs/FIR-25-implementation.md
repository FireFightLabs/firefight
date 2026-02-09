# FIR-25: Phase 1.4 — Incident Creation Modal & Flow

## Overview

Wire the incident creation modal submission to an `IncidentCreationWorkflow` that creates the incident record, Slack channel, quick-actions message, announcement in #incidents, and initial event log.

**This is the largest ticket.** It touches the modal submission pipeline, creates a 7-step workflow, adds two new Slack adapter/builder classes, and extends `Slack::Client` with `pin_message`.

---

## Current State Audit

| Component | Status | Detail |
|---|---|---|
| `Slack::ModalBuilder.incident_creation_form` | **Done** | Modal with name, severity, summary (+ visibility from FIR-24) |
| `InteractionsController` — `view_submission` | **Partial** | Routes by callback_id, only handles `share_incidents_channel_modal` |
| `SlackInteractionsService` — incident modal handler | **Missing** | No `incident_creation_modal` handler |
| `IncidentCreationWorkflow` | **Missing** | Not created |
| Workflow `Base` class | **Done** | `step`, `start!`, `start_inline!`, dependencies, retries |
| `Incident` model | **Done** | Full schema with sequencing, channel naming, lifecycle concerns |
| `IncidentEvent` model | **Done** | `INCIDENT_CREATED` constant, `metadata` jsonb |
| `IncidentStatus.default_status` / `IncidentSeverity.default_severity` | **Done** | Scopes exist, fixtures have `is_default: true` |
| `Slack::Client.create_channel` | **Done** | Supports `is_private`, raises `ChannelExistsError` |
| `Slack::Client.set_channel_topic/purpose` | **Done** | Both exist |
| `Slack::Client.invite_to_channel` | **Done** | Exists |
| `Slack::Client.post_message` | **Done** | Exists |
| `Slack::Client.pin_message` | **Missing** | Not implemented |
| `Slack::WorkspaceAdapter` — generic channel creation | **Partial** | Has `create_incidents_channel` (hardcoded "incidents") but no generic `create_channel(name:, is_private:)` |
| `Slack::IncidentMessageBuilder` | **Missing** | No quick-actions or announcement block builders |
| Incident fixtures | **Done** | 7 incidents across 2 workspaces |
| `SlackClientStubHelper` | **Done** | Has stubs for channel, message, modal operations |

---

## Architecture Decisions

### 1. Workflow Subject: Create Incident First, Then Start Workflow

The ticket proposes passing `nil` as the workflow subject and updating it in the first step. But the `Workflow` model **validates presence** of `subject_type` and `subject_id`, and `Base.create_workflow!` calls `subject.class.name` which would raise `NoMethodError` on nil.

**Solution:** Create the incident record in the submission handler (before the workflow), then start the workflow with the incident as the subject. The workflow handles the Slack-side setup (channel, messages, invites).

```
Modal submission → Create Incident record → Start workflow(incident) → Channel, messages, events
```

### 2. Extend WorkspaceAdapter with Generic Channel Creation

The existing `create_incidents_channel` is hardcoded. We need a generic `create_channel(name:, is_private:)` method on the adapter that incident creation can use.

### 3. Severity/Status Lookup by Slug

The modal sends severity values like `"critical"`, `"major"`, `"minor"` — these match the `slug` column on `IncidentSeverity`. The handler looks up `IncidentSeverity` and `IncidentStatus` (default) by workspace scope.

---

## Implementation Steps

### Step 1: Add `Slack::Client.pin_message`

**File:** `app/adapters/slack/client.rb`

```ruby
# Pin a message in a channel
#
# @param workspace [Workspace] The workspace to use for authentication
# @param channel [String] Channel ID
# @param timestamp [String] Message timestamp to pin
# @return [Hash] Slack API response
# @raise [ApiError] if Slack API returns an error
def self.pin_message(workspace:, channel:, timestamp:)
  api_post(
    workspace: workspace,
    endpoint: "pins.add",
    payload: {
      channel: channel,
      timestamp: timestamp
    }
  )
end
```

### Step 2: Add `stub_pin_message` to Test Helper

**File:** `test/support/slack_client_stub_helper.rb`

```ruby
def stub_pin_message
  Slack::Client.stubs(:pin_message).returns({ ok: true })
end
```

Update `stub_successful_slack_workflow` to include `stub_pin_message`.

### Step 3: Add Generic `create_channel` to WorkspaceAdapter

**File:** `app/adapters/slack/workspace_adapter.rb`

```ruby
# Create a Slack channel with given name
#
# @param name [String] Channel name
# @param is_private [Boolean] Whether channel is private
# @return [Hash] { channel_id:, channel_name: }
def create_channel(name:, is_private: false)
  result = Slack::Client.create_channel(
    workspace: @workspace,
    name: name,
    is_private: is_private
  )

  {
    channel_id: result[:channel][:id],
    channel_name: result[:channel][:name]
  }
end
```

### Step 4: Create `Slack::IncidentMessageBuilder`

**File:** `app/adapters/slack/incident_message_builder.rb`

Build two Block Kit message payloads:

```ruby
module Slack
  class IncidentMessageBuilder
    # Quick actions message posted and pinned in incident channel
    def self.quick_actions_blocks(incident)
      [
        {
          type: "header",
          text: {
            type: "plain_text",
            text: "#{incident.identifier}: #{incident.name || 'Untitled Incident'}"
          }
        },
        {
          type: "section",
          text: {
            type: "mrkdwn",
            text: [
              "*Severity:* #{severity_emoji(incident.incident_severity)} #{incident.incident_severity.name}",
              "*Status:* #{incident.incident_status.name}",
              "*Declared by:* <@#{incident.declared_by.platform_user_id}>"
            ].join("\n")
          }
        },
        { type: "divider" },
        {
          type: "actions",
          elements: [
            {
              type: "button",
              text: { type: "plain_text", text: "Make me Lead" },
              action_id: "set_incident_lead_self",
              value: incident.id
            },
            {
              type: "button",
              text: { type: "plain_text", text: "Update summary" },
              action_id: "update_incident_summary",
              value: incident.id
            }
          ]
        }
      ]
    end

    # Announcement posted to #incidents channel
    def self.announcement_blocks(incident)
      [
        {
          type: "section",
          text: {
            type: "mrkdwn",
            text: [
              "*New incident declared*",
              "",
              "*#{incident.identifier}* #{incident.name || 'Untitled Incident'}",
              "*Severity:* #{severity_emoji(incident.incident_severity)} #{incident.incident_severity.name} | *Status:* #{incident.incident_status.name}",
              "",
              "Declared by: <@#{incident.declared_by.platform_user_id}>",
              "Channel: <##{incident.slack_channel_id}>"
            ].join("\n")
          }
        }
      ]
    end

    def self.severity_emoji(severity)
      case severity.slug
      when "critical" then ":red_circle:"
      when "major" then ":large_yellow_circle:"
      when "minor" then ":large_green_circle:"
      else ":white_circle:"
      end
    end
  end
end
```

**Notes:**
- Uses `incident.incident_severity` (association) instead of raw string for workspace-configurable severities
- Emoji uses Slack shortcodes (`:red_circle:`) instead of Unicode for cross-platform consistency

### Step 5: Create `IncidentCreationWorkflow`

**File:** `app/workflows/incident_creation_workflow.rb`

```ruby
class IncidentCreationWorkflow < Base
  workflow_name "incident.creation.v1"

  step :create_slack_channel
  step :set_channel_metadata, depends_on: [:create_slack_channel]
  step :post_quick_actions_message, depends_on: [:set_channel_metadata]
  step :post_announcement, depends_on: [:create_slack_channel]
  step :invite_declarer, depends_on: [:create_slack_channel]
  step :create_incident_event

  def create_slack_channel(workflow:, step:, input:)
    incident = workflow.subject
    workspace = incident.workspace
    adapter = Slack::WorkspaceAdapter.new(workspace)

    result = adapter.create_channel(
      name: incident.channel_name,
      is_private: incident.is_private
    )

    incident.update!(
      slack_channel_id: result[:channel_id],
      slack_channel_name: result[:channel_name]
    )

    { channel_id: result[:channel_id] }
  rescue Slack::Client::ChannelExistsError
    # Handle duplicate by appending timestamp
    fallback_name = "#{incident.channel_name}-#{Time.current.to_i}"
    result = adapter.create_channel(name: fallback_name, is_private: incident.is_private)

    incident.update!(
      slack_channel_id: result[:channel_id],
      slack_channel_name: result[:channel_name]
    )

    { channel_id: result[:channel_id] }
  end

  def set_channel_metadata(workflow:, step:, input:)
    incident = workflow.subject
    workspace = incident.workspace
    channel_id = input["create_slack_channel"]["channel_id"]

    topic = "Severity: #{incident.incident_severity.name} | Status: #{incident.incident_status.name}"
    purpose = "Incident response channel for #{incident.identifier}"

    Slack::Client.set_channel_topic(workspace: workspace, channel: channel_id, topic: topic)
    Slack::Client.set_channel_purpose(workspace: workspace, channel: channel_id, purpose: purpose)

    { ok: true }
  end

  def post_quick_actions_message(workflow:, step:, input:)
    incident = workflow.subject
    workspace = incident.workspace
    blocks = Slack::IncidentMessageBuilder.quick_actions_blocks(incident)

    result = Slack::Client.post_message(
      workspace: workspace,
      channel: incident.slack_channel_id,
      text: "#{incident.identifier} - Quick Actions",
      blocks: blocks
    )

    Slack::Client.pin_message(
      workspace: workspace,
      channel: incident.slack_channel_id,
      timestamp: result[:ts]
    )

    incident.update!(initial_message_ts: result[:ts])

    { message_ts: result[:ts] }
  end

  def post_announcement(workflow:, step:, input:)
    incident = workflow.subject
    workspace = incident.workspace
    incidents_channel_id = workspace.incidents_channel_id

    return { skipped: true } unless incidents_channel_id

    blocks = Slack::IncidentMessageBuilder.announcement_blocks(incident)

    result = Slack::Client.post_message(
      workspace: workspace,
      channel: incidents_channel_id,
      text: "New incident: #{incident.identifier}",
      blocks: blocks
    )

    incident.update!(announcement_message_ts: result[:ts])

    { message_ts: result[:ts] }
  end

  def invite_declarer(workflow:, step:, input:)
    incident = workflow.subject
    workspace = incident.workspace

    Slack::Client.invite_to_channel(
      workspace: workspace,
      channel: incident.slack_channel_id,
      users: incident.declared_by.platform_user_id
    )

    { ok: true }
  end

  def create_incident_event(workflow:, step:, input:)
    incident = workflow.subject

    IncidentEvent.create!(
      incident: incident,
      user: incident.declared_by,
      event_type: IncidentEvent::INCIDENT_CREATED,
      metadata: {
        "severity" => incident.incident_severity.slug,
        "is_private" => incident.is_private
      }
    )

    { ok: true }
  end
end
```

**Dependency graph:**
```
create_slack_channel ──┬── set_channel_metadata ── post_quick_actions_message
                       ├── post_announcement
                       └── invite_declarer
create_incident_event (independent, no deps)
```

### Step 6: Add Modal Submission Handler to SlackInteractionsService

**File:** `app/services/slack_interactions_service.rb`

```ruby
def handle_incident_creation_modal(payload)
  workspace = find_workspace(payload)
  user_id = payload.dig("user", "id")

  member = workspace.workspace_memberships.find_by!(platform_user_id: user_id)

  # Parse modal values
  values = payload.dig("view", "state", "values")
  name = values.dig("name_block", "name_input", "value")
  severity_slug = values.dig("severity_block", "severity_select", "selected_option", "value")
  summary = values.dig("summary_block", "summary_input", "value")
  visibility = values.dig("visibility_block", "visibility_select", "selected_option", "value")

  # Look up configurable severity and default status
  severity = workspace.incident_severities.active.find_by!(slug: severity_slug)
  status = workspace.incident_statuses.default_status

  # Create incident record
  incident = Incident.create!(
    workspace: workspace,
    declared_by: member,
    incident_status: status,
    incident_severity: severity,
    name: name,
    summary: summary,
    is_private: visibility == "private"
  )

  # Start workflow with incident as subject
  IncidentCreationWorkflow.start!(incident)

  Rails.logger.info({
    event: "incident.creation_started",
    incident_id: incident.id,
    identifier: incident.identifier,
    workspace_id: workspace.id,
    severity: severity_slug
  })

  nil # Close the modal
rescue ActiveRecord::RecordNotFound => e
  Rails.logger.error({
    event: "incident.creation_error",
    error: e.message,
    workspace_id: workspace&.id
  })

  {
    response_action: "errors",
    errors: { severity_block: "Invalid severity selection. Please try again." }
  }
rescue => e
  Rails.logger.error({
    event: "incident.creation_error",
    error: e.message,
    backtrace: e.backtrace&.first(5)
  })

  {
    response_action: "errors",
    errors: { name_block: "Failed to create incident. Please try again." }
  }
end
```

### Step 7: Wire Submission Handler in InteractionsController

**File:** `app/controllers/api/v1/interactions_controller.rb`

Add case to `handle_view_submission`:

```ruby
when "incident_creation_modal"
  result = service.handle_incident_creation_modal(payload)
  if result
    render json: result
  else
    head :ok
  end
```

### Step 8: Write Tests

#### 8a. IncidentCreationWorkflow tests

**File:** `test/workflows/incident_creation_workflow_test.rb`

Key test cases:
- Creates channel and updates incident with channel_id
- Sets channel topic and purpose
- Posts quick actions message and pins it
- Posts announcement to #incidents channel
- Skips announcement when workspace has no incidents_channel_id
- Invites declarer to channel
- Creates IncidentEvent with INCIDENT_CREATED type
- Handles channel name collision gracefully
- All 6 steps succeed in correct dependency order

Uses `start_inline!` for synchronous execution in tests with `stub_successful_slack_workflow` + `stub_pin_message`.

#### 8b. SlackInteractionsService — modal submission tests

**File:** `test/services/slack_interactions_service_test.rb` (append)

Key test cases:
- Creates incident from valid modal submission
- Starts IncidentCreationWorkflow with incident as subject
- Handles missing severity gracefully (returns validation error)
- Sets `is_private` correctly based on visibility selection
- Uses workspace's default status
- Creates incident with correct declared_by

#### 8c. InteractionsController — modal submission test

**File:** `test/controllers/api/v1/interactions_controller_test.rb` (append)

Key test case:
- POST with `incident_creation_modal` callback_id creates incident and returns 200

---

## File Summary

| Action | File | Description |
|---|---|---|
| **Edit** | `app/adapters/slack/client.rb` | Add `pin_message` method |
| **Edit** | `app/adapters/slack/workspace_adapter.rb` | Add generic `create_channel` method |
| **Create** | `app/adapters/slack/incident_message_builder.rb` | Quick-actions + announcement blocks |
| **Create** | `app/workflows/incident_creation_workflow.rb` | 6-step workflow |
| **Edit** | `app/services/slack_interactions_service.rb` | Add `handle_incident_creation_modal` |
| **Edit** | `app/controllers/api/v1/interactions_controller.rb` | Add `incident_creation_modal` routing |
| **Edit** | `test/support/slack_client_stub_helper.rb` | Add `stub_pin_message` |
| **Create** | `test/workflows/incident_creation_workflow_test.rb` | Workflow tests |
| **Edit** | `test/services/slack_interactions_service_test.rb` | Modal submission tests |
| **Edit** | `test/controllers/api/v1/interactions_controller_test.rb` | Controller submission test |

## Dependencies

- **FIR-24** must be complete (visibility field in modal, shortcut routing in controller)
- `Incident` model with sequencing, channel naming, lifecycle concerns — **Done**
- `IncidentEvent` model with `INCIDENT_CREATED` — **Done**
- `IncidentStatus.default_status` / `IncidentSeverity` by slug — **Done**
- Workflow engine (`Base` class, `RunStepJob`, `OrchestrateJob`) — **Done**
