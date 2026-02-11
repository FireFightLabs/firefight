# Phase 2: Update Summary, Set Incident Lead, Quick Action Buttons

Implementation doc for FIR-27, FIR-28, FIR-29.

## Overview

Phase 1 created the incident creation workflow: channel, quick actions message (pinned), and announcement. The quick action buttons and `/ff` subcommands currently return placeholder responses. This phase makes them functional.

### What's Being Built

| Issue | Feature | Entry Points |
|-------|---------|-------------|
| FIR-27 | Update Summary | `/ff summary`, "Update summary" button |
| FIR-28 | Set Incident Lead | `/ff lead`, lead modal submission |
| FIR-29 | Quick Action Buttons | "Make me Lead" button, "Update summary" button, "Escalate" button |

## Data Flow

### `/ff summary` Command Flow

```
User types: /ff summary (in incident channel)
     |
[ProcessCommandJob]
     |
     +-> Slack::CommandAdapter.parse(payload)
     +-> CommandDispatcher.find(command)
     |   +-> Commands::Firefight::HomeHandler
     |       +-> case "summary" -> SummaryHandler.execute(command)
     |
[SummaryHandler]
     |
     +-> Find incident by channel_id (workspace.incidents.active.in_channel)
     +-> adapter.open_summary_modal(trigger_id:, incident:)
     |   +-> ModalBuilder.summary_modal(incident) <- pre-fills current summary
     |   +-> Slack::Client.open_modal(...)
     |
     +-> Modal appears in Slack
```

### Summary Modal Submission Flow

```
User submits summary modal
     |
[InteractionsController]
     |
     +-> InteractionNormalizer.call(payload)
     |   +-> Interaction(type: "view_submission",
     |       callback_id: "update_summary_modal",
     |       private_metadata: "<incident_id>",
     |       values: { summary_block: { summary_input: { value: "..." } } })
     |
     +-> InteractionDispatcher.dispatch(interaction)
     |   +-> UpdateSummaryHandler.execute(interaction)
     |
[UpdateSummaryHandler]
     |
     +-> incident = Incident.find(interaction.private_metadata)
     +-> incident.record_change!(INCIDENT_UPDATED) { incident.update!(summary:) }
     +-> IncidentUpdateService
     |   +-> update_quick_actions(incident)  <- chat.update pinned message
     |   +-> update_announcement(incident)   <- chat.update #incidents post
     +-> adapter.post_message("Summary updated by <@user>")
     +-> return nil (close modal)
```

### "Make me Lead" Button Flow

```
User clicks "Make me Lead" button (in pinned quick actions message)
     |
[InteractionsController]
     |
     +-> InteractionNormalizer.call(payload)
     |   +-> Interaction(type: "block_actions",
     |       action_id: "set_incident_lead_self",
     |       action_value: "<incident_id>")
     |
     +-> InteractionDispatcher.dispatch(interaction)
     |   +-> SetLeadSelfHandler.execute(interaction)
     |
[SetLeadSelfHandler]
     |
     +-> incident = Incident.find(interaction.action_value)
     +-> member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)
     +-> incident.record_change!(LEAD_ASSIGNED) { incident.lead = member }
     +-> IncidentUpdateService
     |   +-> update_channel_topic(incident)  <- adds lead name to topic
     |   +-> update_quick_actions(incident)  <- refreshes pinned message
     |   +-> update_announcement(incident)   <- refreshes #incidents post
     +-> adapter.post_lead_expectations(...)  <- ephemeral to new lead
     +-> adapter.post_message("<@user> is now the Incident Lead")
```

### `/ff lead` Modal Flow

```
User types: /ff lead (in incident channel)
     |
[LeadHandler]
     |
     +-> Find incident by channel_id
     +-> adapter.open_lead_modal(trigger_id:, incident:)
     |   +-> ModalBuilder.lead_modal(incident) <- users_select, pre-selects current lead
     |
     +-> Modal appears in Slack
     |
User selects person and submits
     |
[SetLeadHandler]
     |
     +-> incident = Incident.find(interaction.private_metadata)
     +-> selected_user_id = values.dig("lead_block", "lead_select", "selected_user")
     +-> member = workspace.workspace_memberships.find_by!(platform_user_id: selected_user_id)
     +-> incident.record_change!(LEAD_ASSIGNED) { incident.lead = member }
     +-> (same side effects as SetLeadSelfHandler)
```

## Foundation Changes

### Interaction Model

New attrs needed for button values and modal metadata passing:

- `action_value` - extracted from `payload.dig("actions", 0, "value")` (button value containing incident ID)
- `private_metadata` - extracted from `payload.dig("view", "private_metadata")` (modal round-trip data)

### New Identifiers

```
SET_INCIDENT_LEAD_SELF    -> "set_incident_lead_self"     (button action_id)
UPDATE_INCIDENT_SUMMARY   -> "update_incident_summary"    (button action_id)
ESCALATE_INCIDENT         -> "escalate_incident"          (button action_id)
UPDATE_SUMMARY_MODAL      -> "update_summary_modal"       (modal callback_id)
SET_LEAD_MODAL            -> "set_lead_modal"             (modal callback_id)
```

The first two replace hardcoded strings in `IncidentMessageBuilder.quick_actions_blocks`.

### New Slack API Method: `chat.update`

`Slack::Client.update_message` - needed to refresh pinned quick actions message and announcement when summary/lead changes. Same pattern as `post_message` but with additional `ts` parameter.

### IncidentUpdateService

Shared service for post-update side effects. Called by all handlers that modify incident state:

```
IncidentUpdateService#update_quick_actions  -> chat.update on pinned message
IncidentUpdateService#update_announcement   -> chat.update on #incidents post
IncidentUpdateService#update_channel_topic  -> conversations.setTopic with lead name
```

Each method is independently callable and guards against missing timestamps (no-op if message hasn't been posted yet).

## New Files

```
app/services/incident_update_service.rb
app/services/commands/firefight/summary_handler.rb
app/services/commands/firefight/lead_handler.rb
app/services/interactions/update_summary_handler.rb
app/services/interactions/set_lead_handler.rb
app/services/interactions/set_lead_self_handler.rb
app/services/interactions/update_summary_button_handler.rb
app/services/interactions/escalate_placeholder_handler.rb

test/services/incident_update_service_test.rb
test/services/commands/firefight/summary_handler_test.rb
test/services/commands/firefight/lead_handler_test.rb
test/services/interactions/update_summary_handler_test.rb
test/services/interactions/set_lead_handler_test.rb
test/services/interactions/set_lead_self_handler_test.rb
test/services/interactions/update_summary_button_handler_test.rb
```

## Modified Files

```
app/models/interaction.rb                        <- action_value, private_metadata attrs
app/models/identifiers.rb                        <- 5 new constants
app/models/incident.rb                           <- in_channel scope
app/models/workspace_membership.rb               <- display_name delegation
app/adapters/slack/interaction_normalizer.rb      <- extract action_value, private_metadata
app/adapters/slack/client.rb                     <- update_message method
app/adapters/slack/workspace_adapter.rb          <- 5 high-level methods + update_message
app/adapters/slack/modal_builder.rb              <- summary_modal, lead_modal
app/adapters/slack/incident_message_builder.rb   <- use Identifiers constants
app/services/interaction_dispatcher.rb           <- 5 new handler routes
app/services/commands/firefight/home_handler.rb  <- wire summary + lead subcommands
test/support/slack_client_stub_helper.rb         <- stub_update_message
```

## Dispatcher Routing (Final State)

```ruby
# InteractionDispatcher after Phase 2

VIEW_SUBMISSION_HANDLERS = {
  SHARE_INCIDENTS_CHANNEL_MODAL => ShareModalSubmissionHandler,
  INCIDENT_CREATION_MODAL       => IncidentCreationHandler,
  UPDATE_SUMMARY_MODAL          => UpdateSummaryHandler,       # NEW
  SET_LEAD_MODAL                => SetLeadHandler              # NEW
}

BLOCK_ACTION_HANDLERS = {
  PREVIEW_ANNOUNCEMENT       => PreviewAnnouncementHandler,
  SHARE_INCIDENTS_CHANNEL    => ShareChannelHandler,
  PREVIEW_HOMEPAGE_DISABLED  => NoopHandler,
  PREVIEW_SUBSCRIBE_DISABLED => NoopHandler,
  HOME_ACTION_SELECT         => HomeActionSelectHandler,
  SET_INCIDENT_LEAD_SELF     => SetLeadSelfHandler,            # NEW
  UPDATE_INCIDENT_SUMMARY    => UpdateSummaryButtonHandler,    # NEW
  ESCALATE_INCIDENT          => EscalatePlaceholderHandler     # NEW
}
```

## Event Types Used

- `IncidentEvent::INCIDENT_UPDATED` - summary changes
- `IncidentEvent::LEAD_ASSIGNED` - lead assignment (both modal and button)

Both use `incident.record_change!` for before/after snapshots.
