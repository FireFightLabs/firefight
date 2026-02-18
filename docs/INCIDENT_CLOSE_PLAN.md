# FIR-38: Close/Resolve Incident — Implementation Plan

## Overview

Implement `/ff close` and `/ff resolve` commands to close incidents with resolution details and metrics display, and `/ff reopen` to reopen closed incidents.

**Close flow**: When a user runs `/ff close` or `/ff resolve` from an incident channel, a modal opens pre-filled with the current summary. Upon submission, the incident status transitions to a closed category, `resolved_at` is auto-set by the `Lifecycle` concern, metrics are calculated, and all Slack surfaces (channel topic, quick actions, announcement, announcement thread) are updated.

**Reopen flow**: When a user runs `/ff reopen` from a closed incident channel, the incident status transitions back to a live category (the workspace default status), `resolved_at` is cleared by the `Lifecycle` concern, a reopen message is posted, and all Slack surfaces are updated. No modal needed — reopening is immediate.

---

## Step 1: Identifiers & Event Types

**File**: `app/models/identifiers.rb`

Add:
```ruby
CLOSE_INCIDENT_MODAL = "close_incident_modal"
```

**File**: `app/models/incident_event.rb`

Add new event type constant and include it in `EVENT_TYPES`:
```ruby
INCIDENT_REOPENED = "incident.reopened"
```

---

## Step 2: Modal Builder — Close Incident Modal

**File**: `app/adapters/slack/modal_builder.rb`

### `close_modal(incident)`

- callback_id: `Identifiers::CLOSE_INCIDENT_MODAL`
- notify_on_close: true (for temp message cleanup)
- private_metadata: JSON with `{ incident_id, temp_message_ts, channel_id }`
- Title: "Close incident"
- Submit: "Close incident"
- Close: "Cancel"

**Fields:**

1. **Incident info** — read-only section showing `*INC-XX*: Incident Name`
2. **Summary** — pre-filled textarea (block_id: `summary_block`, action_id: `summary_input`) with current `incident.summary`. The responder can update the summary as part of closing. Optional — if blank, summary stays as-is.
3. **Metadata section** — read-only context block:
   - Severity: current severity name
   - Lead: current lead display name or "Not assigned"
   - Declared at: formatted timestamp

This keeps the modal simple. The status is implicitly set to the workspace's closed status — no need for a status dropdown.

---

## Step 3: Message Builder — Resolution Message

**File**: `app/adapters/slack/incident_message_builder.rb`

### `resolution_blocks(incident, resolved_by_platform_user_id:)`

Posted to the incident channel when the incident is resolved. Format:

```
:white_check_mark:  *Incident Resolved*
---
> [Summary or "No summary provided"]

Resolved by: @user
Severity: Critical
Time to resolve: 2h 34m
```

Implementation details:
- Header section with check emoji and bold title
- Divider
- Quoted summary section (or italic "No summary provided")
- Context block with: resolved by, severity, time to resolve (formatted as duration)

### `resolution_announcement_thread_blocks(incident, resolved_by_platform_user_id:)`

Posted as a reply to the announcement in #incidents channel. Same structure as `resolution_blocks` but uses the vertical announcement thread style (sections instead of context, with divider).

### `reopen_blocks(incident, reopened_by_platform_user_id:)`

Posted to the incident channel when the incident is reopened. Format:

```
:rotating_light:  *Incident Reopened*
---
Reopened by: @user
Status: Investigating
```

Implementation details:
- Header section with rotating light emoji and bold title
- Divider
- Context block with: reopened by, new status name

### `reopen_announcement_thread_blocks(incident, reopened_by_platform_user_id:)`

Posted as a thread reply in #incidents. Same structure as `reopen_blocks` but uses vertical announcement thread style.

### Private helper: `format_duration(minutes)`

Converts minutes to human-readable format:
- < 60: "Xm"
- 60-1440: "Xh Ym"
- >= 1440: "Xd Yh"

Returns "N/A" if nil.

---

## Step 4: Adapter — High-Level Methods

**File**: `app/adapters/slack/workspace_adapter.rb`

### `open_close_incident_modal(trigger_id:, incident:, private_metadata: nil)`

Opens the close modal:
```ruby
def open_close_incident_modal(trigger_id:, incident:, private_metadata: nil)
  open_modal(
    trigger_id: trigger_id,
    view: Slack::ModalBuilder.close_modal(incident, private_metadata: private_metadata)
  )
end
```

### `post_resolution_message(channel_id:, incident:, resolved_by_platform_user_id:)`

Posts the resolution message to the incident channel.

### `post_resolution_announcement_thread(channel_id:, thread_ts:, incident:, resolved_by_platform_user_id:)`

Posts resolution details as a thread reply to the #incidents announcement.

### `post_reopen_message(channel_id:, incident:, reopened_by_platform_user_id:)`

Posts the reopen message to the incident channel.

### `post_reopen_announcement_thread(channel_id:, thread_ts:, incident:, reopened_by_platform_user_id:)`

Posts reopen details as a thread reply to the #incidents announcement.

---

## Step 5: CloseModalOpener Service

**File**: `app/services/close_modal_opener.rb` (new)

Follows the same pattern as `SummaryModalOpener` and `IncidentUpdateModalOpener`:

1. Posts a temporary message: `:lock: <@user_id> is closing the incident...`
2. Packs temp message info into `private_metadata` JSON
3. Opens the close modal via adapter
4. On `TriggerExpired`, cleans up the temp message

```ruby
class CloseModalOpener
  def self.open(workspace:, incident:, trigger_id:, user_id:)
    adapter = WorkspaceAdapter.for(workspace)

    result = adapter.post_message(
      channel_id: incident.channel_id,
      text: ":lock: <@#{user_id}> is closing the incident...",
      blocks: nil
    )

    metadata = {
      incident_id: incident.id,
      temp_message_ts: result[:message_ts],
      channel_id: incident.channel_id
    }.to_json

    adapter.open_close_incident_modal(trigger_id: trigger_id, incident: incident, private_metadata: metadata)
  rescue AdapterError::TriggerExpired
    cleanup_temp_message(adapter, incident.channel_id, result&.dig(:message_ts))
    raise
  end

  def self.cleanup_temp_message(adapter, channel_id, ts)
    return unless ts
    adapter.delete_message(channel_id: channel_id, ts: ts)
  rescue AdapterError, Slack::Client::ApiError => e
    Rails.logger.warn({ event: "close_modal_opener.cleanup_temp_failed", error: e.message })
  end
  private_class_method :cleanup_temp_message
end
```

---

## Step 6: Command Handler — `/ff close` and `/ff resolve`

**File**: `app/services/commands/firefight/close_handler.rb` (new)

Pattern follows `StatusHandler`:

```ruby
module Commands
  module Firefight
    class CloseHandler
      def self.execute(command)
        workspace = command.workspace
        return ephemeral("Workspace not found. Please reinstall Firefight.") unless workspace

        incident = workspace.incidents.active.in_channel(command.channel_id).first
        return ephemeral("This command must be run from an active incident channel.") unless incident

        CloseModalOpener.open(
          workspace: workspace,
          incident: incident,
          trigger_id: command.trigger_id,
          user_id: command.user_id
        )
        nil
      rescue AdapterError::TriggerExpired
        ephemeral("This command has expired. Please try `/ff close` again.")
      end

      private_class_method def self.ephemeral(text)
        { response_type: "ephemeral", text: text }
      end
    end
  end
end
```

### Wire in HomeHandler

**File**: `app/services/commands/firefight/home_handler.rb`

Change:
```ruby
when "close", "resolve"
  # Phase 5.1
  ephemeral("Close command coming soon...")
```
To:
```ruby
when "close", "resolve"
  Commands::Firefight::CloseHandler.execute(command)
when "reopen"
  Commands::Firefight::ReopenHandler.execute(command)
```

---

## Step 6b: Command Handler — `/ff reopen`

**File**: `app/services/commands/firefight/reopen_handler.rb` (new)

Reopening is immediate (no modal needed):

```ruby
module Commands
  module Firefight
    class ReopenHandler
      def self.execute(command)
        workspace = command.workspace
        return ephemeral("Workspace not found. Please reinstall Firefight.") unless workspace

        incident = workspace.incidents.closed.in_channel(command.channel_id).first
        return ephemeral("This command must be run from a closed incident channel.") unless incident

        member = workspace.workspace_memberships.find_by!(platform_user_id: command.user_id)
        default_status = workspace.incident_statuses.live.find_by(is_default: true) || workspace.incident_statuses.live.first

        incident.record_change!(IncidentEvent::INCIDENT_REOPENED, changed_by: member) do
          incident.update!(incident_status: default_status)
        end

        IncidentReopenWorkflow.start!(incident, context: {
          reopened_by_platform_user_id: command.user_id
        })

        nil
      end

      private_class_method def self.ephemeral(text)
        { response_type: "ephemeral", text: text }
      end
    end
  end
end
```

Key behavior:
- Finds a **closed** incident in the current channel (not active)
- Uses the workspace default live status (or first live status) to reopen
- `Lifecycle` concern auto-clears `resolved_at` when status moves back to live
- Starts `IncidentReopenWorkflow` for Slack surface updates
- No modal — returns nil (ephemeral response is empty)

---

## Step 7: IncidentUpdateService — New Methods

**File**: `app/services/incident_update_service.rb`

Add methods for the close workflow to delegate to:

### `post_resolution_message(incident, resolved_by_platform_user_id:)`
```ruby
def post_resolution_message(incident, resolved_by_platform_user_id:)
  adapter = WorkspaceAdapter.for(@workspace)
  adapter.post_resolution_message(
    channel_id: incident.channel_id,
    incident: incident,
    resolved_by_platform_user_id: resolved_by_platform_user_id
  )
end
```

### `post_resolution_announcement_thread(incident, resolved_by_platform_user_id:)`
```ruby
def post_resolution_announcement_thread(incident, resolved_by_platform_user_id:)
  return unless incident.announcement_message_ts

  adapter = WorkspaceAdapter.for(@workspace)
  adapter.post_resolution_announcement_thread(
    channel_id: @workspace.incidents_channel_id,
    thread_ts: incident.announcement_message_ts,
    incident: incident,
    resolved_by_platform_user_id: resolved_by_platform_user_id
  )
end
```

### `post_reopen_message(incident, reopened_by_platform_user_id:)`
```ruby
def post_reopen_message(incident, reopened_by_platform_user_id:)
  adapter = WorkspaceAdapter.for(@workspace)
  adapter.post_reopen_message(
    channel_id: incident.channel_id,
    incident: incident,
    reopened_by_platform_user_id: reopened_by_platform_user_id
  )
end
```

### `post_reopen_announcement_thread(incident, reopened_by_platform_user_id:)`
```ruby
def post_reopen_announcement_thread(incident, reopened_by_platform_user_id:)
  return unless incident.announcement_message_ts

  adapter = WorkspaceAdapter.for(@workspace)
  adapter.post_reopen_announcement_thread(
    channel_id: @workspace.incidents_channel_id,
    thread_ts: incident.announcement_message_ts,
    incident: incident,
    reopened_by_platform_user_id: reopened_by_platform_user_id
  )
end
```

---

## Step 8: IncidentCloseWorkflow

**File**: `app/workflows/incident_close_workflow.rb` (new)

```ruby
class IncidentCloseWorkflow < Base
  workflow_name "incident.close.v1"

  step :update_channel_topic
  step :update_quick_actions
  step :update_announcement
  step :post_resolution_message
  step :post_resolution_announcement_thread

  def update_channel_topic(workflow:, step:, input:)
    service(workflow).update_channel_topic(workflow.subject)
  end

  def update_quick_actions(workflow:, step:, input:)
    service(workflow).update_quick_actions(workflow.subject)
  end

  def update_announcement(workflow:, step:, input:)
    service(workflow).update_announcement(workflow.subject)
  end

  def post_resolution_message(workflow:, step:, input:)
    service(workflow).post_resolution_message(
      workflow.subject,
      resolved_by_platform_user_id: workflow.context["resolved_by_platform_user_id"]
    )
  end

  def post_resolution_announcement_thread(workflow:, step:, input:)
    service(workflow).post_resolution_announcement_thread(
      workflow.subject,
      resolved_by_platform_user_id: workflow.context["resolved_by_platform_user_id"]
    )
  end

  private

  def service(workflow)
    @service ||= IncidentUpdateService.new(workflow.subject.workspace)
  end
end
```

Steps:
1. **update_channel_topic** — Topic becomes `"Severity: Critical | Status: Resolved | Lead: Alice"` (reuses existing service method)
2. **update_quick_actions** — Refreshes pinned message (buttons may change for closed state)
3. **update_announcement** — Updates the #incidents announcement with resolved status
4. **post_resolution_message** — Posts the resolution message to the incident channel
5. **post_resolution_announcement_thread** — Posts resolution details as a thread reply in #incidents

---

## Step 8b: IncidentReopenWorkflow

**File**: `app/workflows/incident_reopen_workflow.rb` (new)

```ruby
class IncidentReopenWorkflow < Base
  workflow_name "incident.reopen.v1"

  step :update_channel_topic
  step :update_quick_actions
  step :update_announcement
  step :post_reopen_message
  step :post_reopen_announcement_thread

  def update_channel_topic(workflow:, step:, input:)
    service(workflow).update_channel_topic(workflow.subject)
  end

  def update_quick_actions(workflow:, step:, input:)
    service(workflow).update_quick_actions(workflow.subject)
  end

  def update_announcement(workflow:, step:, input:)
    service(workflow).update_announcement(workflow.subject)
  end

  def post_reopen_message(workflow:, step:, input:)
    service(workflow).post_reopen_message(
      workflow.subject,
      reopened_by_platform_user_id: workflow.context["reopened_by_platform_user_id"]
    )
  end

  def post_reopen_announcement_thread(workflow:, step:, input:)
    service(workflow).post_reopen_announcement_thread(
      workflow.subject,
      reopened_by_platform_user_id: workflow.context["reopened_by_platform_user_id"]
    )
  end

  private

  def service(workflow)
    @service ||= IncidentUpdateService.new(workflow.subject.workspace)
  end
end
```

Steps mirror the close workflow but post reopen messages instead of resolution messages.

---

## Step 9: CloseIncidentHandler — Modal Submission

**File**: `app/services/interactions/close_incident_handler.rb` (new)

```ruby
module Interactions
  class CloseIncidentHandler
    def self.execute(interaction)
      workspace = interaction.workspace
      metadata = parse_metadata(interaction.private_metadata)
      incident = workspace.incidents.find(metadata[:incident_id])
      member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)

      return already_closed_error if incident.closed?

      new_summary = interaction.values.dig("summary_block", "summary_input", "value")
      resolved_status = workspace.incident_statuses.closed.first

      incident.record_change!(IncidentEvent::INCIDENT_RESOLVED, changed_by: member) do
        attrs = { incident_status: resolved_status }
        attrs[:summary] = new_summary if new_summary.present?
        incident.update!(attrs)
      end

      IncidentCloseWorkflow.start!(incident, context: {
        resolved_by_platform_user_id: interaction.user_id
      })

      delete_temp_message(workspace, metadata)

      nil
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.warn({ event: "interactions.close_incident.record_not_found", error: e.message })
      delete_temp_message(workspace, metadata) if workspace && metadata
      { response_action: "errors", errors: { "summary_block" => "Something went wrong. Please close this modal and try again." } }
    end

    def self.parse_metadata(raw)
      parsed = JSON.parse(raw)
      { incident_id: parsed["incident_id"], temp_message_ts: parsed["temp_message_ts"], channel_id: parsed["channel_id"] }
    rescue JSON::ParserError
      { incident_id: raw }
    end
    private_class_method :parse_metadata

    def self.already_closed_error
      { response_action: "errors", errors: { "summary_block" => "This incident is already closed." } }
    end
    private_class_method :already_closed_error

    def self.delete_temp_message(workspace, metadata)
      return unless metadata[:temp_message_ts] && metadata[:channel_id]

      adapter = WorkspaceAdapter.for(workspace)
      adapter.delete_message(channel_id: metadata[:channel_id], ts: metadata[:temp_message_ts])
    rescue AdapterError, Slack::Client::ApiError => e
      Rails.logger.warn({ event: "interactions.close_incident.delete_temp_failed", error: e.message })
    end
    private_class_method :delete_temp_message
  end
end
```

Key behavior:
- Fetches the first `closed` category status from the workspace (e.g., "Resolved")
- Uses `record_change!` with `INCIDENT_RESOLVED` event type for full before/after snapshots
- Updates summary if a new value was provided
- `Lifecycle` concern auto-sets `resolved_at` and clears `next_update_at`
- Starts `IncidentCloseWorkflow` for all Slack surface updates
- Cleans up temp message
- Guards against double-close

---

## Step 10: Wire Dispatchers

**File**: `app/services/interaction_dispatcher.rb`

Add to `VIEW_SUBMISSION_HANDLERS`:
```ruby
Identifiers::CLOSE_INCIDENT_MODAL => Interactions::CloseIncidentHandler
```

**File**: `app/services/interactions/view_closed_handler.rb`

Add `Identifiers::CLOSE_INCIDENT_MODAL` to the list of modals that need temp message cleanup on close:
```ruby
def self.execute(interaction)
  return unless [
    Identifiers::UPDATE_SUMMARY_MODAL,
    Identifiers::INCIDENT_UPDATE_MODAL,
    Identifiers::CLOSE_INCIDENT_MODAL
  ].include?(interaction.callback_id)

  delete_temp_message(interaction)
  nil
end
```

---

## Step 11: Tests

### New Test Files

1. **`test/services/commands/firefight/close_handler_test.rb`**
   - Opens close modal from incident channel
   - Returns ephemeral error when not in incident channel
   - Returns ephemeral error when workspace not found
   - Handles trigger expiration

2. **`test/services/interactions/close_incident_handler_test.rb`**
   - Closes incident and sets resolved status
   - Updates summary when provided
   - Keeps existing summary when input is blank
   - Creates INCIDENT_RESOLVED event with before/after snapshots
   - Auto-sets resolved_at via Lifecycle concern
   - Starts IncidentCloseWorkflow with correct context
   - Returns error when incident already closed
   - Returns error when incident not found
   - Cleans up temp message

3. **`test/services/close_modal_opener_test.rb`**
   - Posts temp message and opens modal
   - Cleans up temp message on trigger expiration

4. **`test/workflows/incident_close_workflow_test.rb`**
   - Full workflow succeeds with all 5 steps
   - Each step delegates to service correctly
   - Handles missing announcement_message_ts gracefully

5. **`test/services/commands/firefight/reopen_handler_test.rb`**
   - Reopens closed incident and sets default live status
   - Returns ephemeral error when not in closed incident channel
   - Returns ephemeral error when workspace not found
   - Creates INCIDENT_REOPENED event with before/after snapshots
   - Clears resolved_at via Lifecycle concern
   - Starts IncidentReopenWorkflow with correct context

6. **`test/workflows/incident_reopen_workflow_test.rb`**
   - Full workflow succeeds with all 5 steps
   - Each step delegates to service correctly
   - Handles missing announcement_message_ts gracefully

### Test Patterns
- Create incidents inline in setup (not from shared fixtures) for parallel safety
- Use `stub_post_message`, `stub_update_message`, `stub_open_modal`, `stub_set_channel_topic`, `stub_pin_message`, `stub_delete_message` from `SlackClientStubHelper`
- Build `Interaction.new(platform: Platforms::SLACK, ...)` objects directly
- Use `Identifiers::` constants, never string literals
- Use `find_by!` with specific attributes, never `Model.last`
- Workflow tests use `start_inline!` for synchronous execution

---

## Implementation Order

1. Identifier (`CLOSE_INCIDENT_MODAL`) + event type (`INCIDENT_REOPENED`)
2. Modal Builder (`close_modal`)
3. Message Builder (`resolution_blocks`, `resolution_announcement_thread_blocks`, `reopen_blocks`, `reopen_announcement_thread_blocks`, `format_duration`)
4. Adapter high-level methods (close + reopen)
5. `CloseModalOpener` service
6. `CloseHandler` command + `ReopenHandler` command + wire in `HomeHandler`
7. `IncidentUpdateService` new methods (close + reopen)
8. `IncidentCloseWorkflow` + `IncidentReopenWorkflow`
9. `CloseIncidentHandler` interaction handler
10. Wire dispatchers (`InteractionDispatcher`, `ViewClosedHandler`)
11. Tests for everything
12. Run `bin/ci`

---

## Verification

1. Run `bin/ci` — all tests pass, rubocop clean, brakeman clean
2. Verify close flow:
   - `/ff close` in incident channel opens modal
   - `/ff resolve` routes to same handler
   - `/ff close` outside incident channel returns ephemeral error
   - Modal pre-filled with current summary
   - Modal shows severity, lead, declared at
   - Submitting sets status to closed category
   - `resolved_at` auto-set by Lifecycle concern
   - `time_to_resolve` computed correctly
   - Resolution message posted to incident channel with metrics
   - Channel topic updated with resolved status
   - Quick actions pinned message updated
   - #incidents announcement updated
   - Resolution thread posted in #incidents
   - INCIDENT_RESOLVED event created with snapshots
   - Already-closed incident shows error in modal
   - Temp message cleaned up on submit and on modal close (X button)
3. Verify reopen flow:
   - `/ff reopen` in closed incident channel reopens immediately
   - `/ff reopen` outside closed incident channel returns ephemeral error
   - Status transitions to workspace default live status
   - `resolved_at` cleared by Lifecycle concern
   - Reopen message posted to incident channel
   - Channel topic updated with new status
   - Quick actions pinned message updated (buttons restored)
   - #incidents announcement updated
   - Reopen thread posted in #incidents
   - INCIDENT_REOPENED event created with snapshots
