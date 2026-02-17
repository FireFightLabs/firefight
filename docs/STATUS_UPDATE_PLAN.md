# FIR-30 / FIR-31 / FIR-32: Status Update Flow, Severity Change, Update Reminders

## Context

Incidents need a way to update status, severity, and communicate progress — all from a single modal. Currently `/ff status` and `/ff severity` are placeholder stubs in `HomeHandler`. This plan implements:

- **FIR-30**: `/ff status` opens "Internal status update" modal (status, severity, message, reminder timer)
- **FIR-31**: `/ff severity` opens the same modal (just an alias)
- **FIR-32**: Optional "next update" timer in the modal schedules a reminder job

All three features share the same modal and submission handler, making them a single cohesive unit.

---

## Step 1: Migration — add `next_update_at`

Add column to `incidents`:
- `next_update_at` (datetime, nullable) — when the next status update is expected

**File**: `db/migrate/..._add_next_update_at_to_incidents.rb`

---

## Step 2: Identifiers

Add to `app/models/identifiers.rb`:

```ruby
INCIDENT_UPDATE_MODAL = "incident_update_modal"
SEND_INCIDENT_UPDATE = "send_incident_update"
```

---

## Step 3: Modal Builder — `incident_update_modal`

Add to `app/adapters/slack/modal_builder.rb`:

```ruby
def self.incident_update_modal(incident, private_metadata: nil)
```

**Modal fields:**
1. **Status** — `static_select` with workspace's active statuses (ordered by position), pre-selected with `incident.incident_status`. Each option includes `description` text from `IncidentStatus#description`.
2. **Severity** — `static_select` with workspace's active severities (ordered by position), pre-selected with `incident.incident_severity`. Each option includes `description` text from `IncidentSeverity#description`.
3. **Message** — optional `plain_text_input`, multiline, max 3000 chars. Placeholder: "What's happening at the moment? What are you doing next?"
4. **When will you provide the next update?** — optional `static_select` with preset durations: 5 min, 15 min, 30 min, 1 hour, 3 hours, 1 day, 7 days. Label includes "(optional)".

`callback_id`: `Identifiers::INCIDENT_UPDATE_MODAL`
`private_metadata`: JSON with `incident_id`, `temp_message_ts`, `channel_id`
`notify_on_close`: true (for temp message cleanup)

Block/action IDs: `status_block`/`status_select`, `severity_block`/`severity_select`, `message_block`/`message_input`, `next_update_block`/`next_update_select`

---

## Step 4: IncidentMessageBuilder — status update messages

Add two methods to `app/adapters/slack/incident_message_builder.rb`:

Both methods share the same signature and diff display logic but produce different Block Kit layouts.

```ruby
def self.status_update_blocks(incident, message:, updated_by_platform_user_id:, previous_status_name: nil, previous_severity_name: nil)
def self.status_update_announcement_blocks(incident, message:, updated_by_platform_user_id:, previous_status_name: nil, previous_severity_name: nil)
```

### `status_update_blocks` — posted in the **incident channel**

Compact inline format:
- Header: "Incident updated"
- Context block (single line): "Updated by: **Name** | Severity: **Minor** | Status: ~Investigating~ → **Fixing**"
- If message present: section block with the message text

### `status_update_announcement_blocks` — threaded reply on **#incidents announcement**

Vertical format with divider:
- Header: "Incident updated"
- Divider
- If message present: section block with the message text
- Context elements (each on its own line):
  - ":bust_in_silhouette: Updated by: **Name**"
  - ":rotating_light: Severity: **Minor**" (or "Severity: ~Minor~ → **Critical**" if changed)
  - ":traffic_light: Status: ~Investigating~ → **Fixing**" (or "Status: **Investigating**" if unchanged)

### Diff display logic (shared)

- If `previous_status_name` differs from current: show `~OldStatus~ → NewStatus` (Slack strikethrough)
- If `previous_severity_name` differs from current: show `~OldSeverity~ → NewSeverity`
- If unchanged: show just the current value

The `IncidentUpdateHandler` passes the previous values (captured before `record_change!`) into the workflow context, which passes them to these builders.

---

## Step 5: Slack::Client — add `thread_ts` support

Add `thread_ts: nil` parameter to `Slack::Client.post_message` and include in payload (compact already handles nil).

**File**: `app/adapters/slack/client.rb`

---

## Step 6: Slack::WorkspaceAdapter — new high-level methods

Add to `app/adapters/slack/workspace_adapter.rb`:

```ruby
def open_incident_update_modal(trigger_id:, incident:, private_metadata: nil)
def post_incident_update_message(channel_id:, incident:, message:, updated_by_platform_user_id:)
def post_threaded_message(channel_id:, thread_ts:, text:, blocks: nil)
```

`post_threaded_message` is a low-level method that wraps `post_message` with `thread_ts`.

---

## Step 7: IncidentUpdateModalOpener service

**New file**: `app/services/incident_update_modal_opener.rb`

Follows `SummaryModalOpener` pattern exactly:
1. Post temp message: ":writing_hand: <@user> is writing an internal status update..."
2. Build private_metadata JSON with `incident_id`, `temp_message_ts`, `channel_id`
3. Open incident update modal via adapter
4. On `TriggerExpired`: cleanup temp message, re-raise

---

## Step 8: StatusHandler command

**New file**: `app/services/commands/firefight/status_handler.rb`

Follows `SummaryHandler` pattern:
1. Find workspace, validate incident channel, find active incident
2. Delegate to `IncidentUpdateModalOpener.open(...)`
3. Return nil on success
4. Rescue `TriggerExpired` with ephemeral error

---

## Step 9: SeverityHandler command (FIR-31)

**New file**: `app/services/commands/firefight/severity_handler.rb`

Identical to `StatusHandler` — both open the same modal. Could extract shared logic, but for now keep them as separate thin handlers (consistent with existing pattern).

---

## Step 10: Wire commands in HomeHandler

Update `app/services/commands/firefight/home_handler.rb`:

```ruby
when "status"
  Commands::Firefight::StatusHandler.execute(command)
when "severity"
  Commands::Firefight::SeverityHandler.execute(command)
```

---

## Step 11: IncidentUpdateHandler interaction handler

**New file**: `app/services/interactions/incident_update_handler.rb`

Handles `VIEW_SUBMISSION` for `INCIDENT_UPDATE_MODAL`:

1. Parse private_metadata JSON
2. Find incident, workspace, acting member
3. Extract form values:
   - `status_slug` from `status_block.status_select.selected_option.value`
   - `severity_slug` from `severity_block.severity_select.selected_option.value`
   - `message` from `message_block.message_input.value` (optional)
   - `next_update_minutes` from `next_update_block.next_update_select.selected_option.value` (optional)
4. Look up `IncidentStatus` and `IncidentSeverity` by slug
5. **Capture previous values** before updating: `previous_status_name = incident.incident_status.name`, `previous_severity_name = incident.incident_severity.name`
6. Use `incident.record_change!(IncidentEvent::INCIDENT_UPDATED, changed_by: member)` to:
   - Update `incident_status` if changed
   - Update `incident_severity` if changed
7. Handle next_update reminder:
   - If `next_update_minutes` present: set `incident.next_update_at = Time.current + minutes.to_i.minutes` and schedule `IncidentUpdateReminderJob`
   - If not present: clear `incident.next_update_at`
8. Start `IncidentUpdateWorkflow` with context: `updated_by_platform_user_id`, `message`, `previous_status_name`, `previous_severity_name`
8. Delete temp message
9. Return nil

Error handling: rescue `RecordNotFound` and return modal errors (same pattern as `UpdateSummaryHandler`).

---

## Step 12: IncidentUpdateWorkflow

**New file**: `app/workflows/incident_update_workflow.rb`

```ruby
class IncidentUpdateWorkflow < Base
  workflow_name "incident.incident_update.v1"

  step :update_channel_topic
  step :update_quick_actions
  step :update_announcement
  step :post_update_message
  step :post_announcement_thread
end
```

Steps delegate to `IncidentUpdateService` for the first three (existing methods).

`post_update_message` posts the "Incident updated" message in the **incident channel** using `status_update_blocks` (compact inline format). This builds a timeline of updates visible to everyone in the channel.

`post_announcement_thread` posts the "Incident updated" message as a **threaded reply** on the original announcement in `#incidents` using `status_update_announcement_blocks` (vertical format with divider). Uses `announcement_message_ts` as `thread_ts`. Skips if `announcement_message_ts` is nil.

The workflow context carries `previous_status_name`, `previous_severity_name`, `message`, and `updated_by_platform_user_id`.

---

## Step 13: Wire interaction handlers

Update `app/services/interaction_dispatcher.rb`:

```ruby
# VIEW_SUBMISSION_HANDLERS:
Identifiers::INCIDENT_UPDATE_MODAL => Interactions::IncidentUpdateHandler

# BLOCK_ACTION_HANDLERS:
Identifiers::SEND_INCIDENT_UPDATE => Interactions::SendIncidentUpdateButtonHandler
```

---

## Step 14: ViewClosedHandler update

Update `app/services/interactions/view_closed_handler.rb` to also handle `INCIDENT_UPDATE_MODAL` temp message cleanup (same pattern as `UPDATE_SUMMARY_MODAL`).

---

## Step 15: IncidentUpdateReminderJob (FIR-32)

**New file**: `app/jobs/incident_update_reminder_job.rb`

```ruby
class IncidentUpdateReminderJob < ApplicationJob
  queue_as :default

  def perform(incident_id, expected_next_update_at)
    incident = Incident.find_by(id: incident_id)
    return unless incident
    return unless incident.active?
    return unless incident.next_update_at&.iso8601 == expected_next_update_at

    target_user = incident.lead || incident.declared_by
    adapter = WorkspaceAdapter.for(incident.workspace)
    adapter.post_ephemeral(
      channel_id: incident.channel_id,
      user_id: target_user.platform_user_id,
      text: reminder_text(incident),
      blocks: reminder_blocks(incident)
    )
  end
end
```

Guards:
- Incident must still exist and be active
- `next_update_at` must match expected value (handles rescheduling — old jobs become no-ops)

Reminder message includes a "Send an update" button with `action_id: Identifiers::SEND_INCIDENT_UPDATE` and `value: incident.id`.

Scheduling (in IncidentUpdateHandler):
```ruby
IncidentUpdateReminderJob.set(wait: minutes.minutes).perform_later(incident.id, incident.next_update_at.iso8601)
```

---

## Step 16: SendIncidentUpdateButtonHandler

**New file**: `app/services/interactions/send_incident_update_button_handler.rb`

Handles the "Send an update" button click from reminder:
1. Find incident from `interaction.action_value`
2. Open incident update modal via `IncidentUpdateModalOpener.open(...)`
3. Return nil
4. Rescue `TriggerExpired` silently

---

## Step 17: Lifecycle concern update

Update `app/models/concerns/incident/lifecycle.rb` to clear `next_update_at` when incident moves to closed status:

```ruby
if incident_status.closed? && resolved_at.nil?
  self.resolved_at = Time.current
  self.next_update_at = nil
end
```

---

## Step 18: Adapter `post_ephemeral` — add blocks support

The current `Slack::WorkspaceAdapter#post_ephemeral` only accepts `text:`. Add `blocks: nil` parameter so the reminder can include the "Send an update" button.

Update in `app/adapters/slack/workspace_adapter.rb` and pass through to `Slack::Client.post_ephemeral` (which already accepts `blocks:`).

---

## Files Summary

| File | Change |
|------|--------|
| `db/migrate/..._add_next_update_at_to_incidents.rb` | **New** — migration |
| `app/models/identifiers.rb` | Add `INCIDENT_UPDATE_MODAL`, `SEND_INCIDENT_UPDATE` |
| `app/adapters/slack/modal_builder.rb` | Add `incident_update_modal` |
| `app/adapters/slack/incident_message_builder.rb` | Add `status_update_blocks`, `status_update_announcement_blocks` |
| `app/adapters/slack/client.rb` | Add `thread_ts:` param to `post_message` |
| `app/adapters/slack/workspace_adapter.rb` | Add `open_incident_update_modal`, `post_incident_update_message`, `post_threaded_message`, update `post_ephemeral` |
| `app/services/incident_update_modal_opener.rb` | **New** — opens modal with temp message |
| `app/services/commands/firefight/status_handler.rb` | **New** — `/ff status` command |
| `app/services/commands/firefight/severity_handler.rb` | **New** — `/ff severity` command (same modal) |
| `app/services/commands/firefight/home_handler.rb` | Wire status/severity subcommands |
| `app/services/interactions/incident_update_handler.rb` | **New** — modal submission handler |
| `app/services/interactions/send_incident_update_button_handler.rb` | **New** — reminder button handler |
| `app/services/interactions/view_closed_handler.rb` | Handle incident update modal close |
| `app/services/interaction_dispatcher.rb` | Add routes for new handlers |
| `app/workflows/incident_update_workflow.rb` | **New** — propagates changes to Slack |
| `app/jobs/incident_update_reminder_job.rb` | **New** — scheduled reminder |
| `app/models/concerns/incident/lifecycle.rb` | Clear `next_update_at` on resolve |

### Test files

| File | Tests |
|------|-------|
| `test/services/commands/firefight/status_handler_test.rb` | **New** — command handler tests |
| `test/services/commands/firefight/severity_handler_test.rb` | **New** — command handler tests |
| `test/services/incident_update_modal_opener_test.rb` | **New** — modal opener tests |
| `test/services/interactions/incident_update_handler_test.rb` | **New** — submission handler tests |
| `test/services/interactions/send_incident_update_button_handler_test.rb` | **New** — button handler tests |
| `test/workflows/incident_update_workflow_test.rb` | **New** — workflow tests |
| `test/jobs/incident_update_reminder_job_test.rb` | **New** — job tests with guards |
| `test/services/interaction_dispatcher_test.rb` | Add routing tests |
| `test/services/interactions/view_closed_handler_test.rb` | Add incident update modal close test |

---

## Key Patterns to Reuse

- `SummaryModalOpener` (`app/services/summary_modal_opener.rb`) — temp message + modal pattern
- `SummaryHandler` (`app/services/commands/firefight/summary_handler.rb`) — command handler pattern
- `UpdateSummaryHandler` (`app/services/interactions/update_summary_handler.rb`) — submission handler pattern
- `SummaryUpdateWorkflow` (`app/workflows/summary_update_workflow.rb`) — workflow pattern
- `IncidentUpdateService` (`app/services/incident_update_service.rb`) — reuse `update_channel_topic`, `update_quick_actions`, `update_announcement`
- `Incident::Snapshots#record_change!` — change tracking with before/after snapshots

---

## Verification

1. `bin/ci` passes
2. `/ff status` in an incident channel opens the modal with current values pre-selected
3. `/ff severity` opens the same modal
4. Temp message appears while modal is open ":writing_hand: @user is writing an internal status update..."
5. Temp message cleaned up on submit or modal close (X button)
6. Submitting with changed status posts "Incident updated" in incident channel with diff: "Status: ~Investigating~ → Fixing"
7. Same "Incident updated" message posted as threaded reply on #incidents announcement
8. Submitting without status/severity change shows current values without strikethrough
9. Channel topic, quick actions, and announcement updated after changes
10. Selecting a reminder time schedules a job; reminder ephemeral appears after the delay
11. Resolving an incident clears `next_update_at`; scheduled reminder job becomes a no-op
12. "Send an update" button in reminder opens the status update modal
