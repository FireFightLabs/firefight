# Incident Actions & Follow-ups Implementation Plan

FIR-33 / FIR-34 / FIR-35 / FIR-36

## Context

Incidents need action items and follow-ups — tasks created during an incident that need to be assigned and completed. The `IncidentAction` model already exists with full schema (action_type, status, description, assignee, slack_message_ts, platform_data JSONB, soft deletes). Event types `ACTION_CREATED`, `ACTION_PICKED_UP`, `ACTION_COMPLETED` are defined in `IncidentEvent` but not yet used.

Actions and follow-ups are **separate flows** with separate modals, commands, and emoji reactions — but share the same underlying `IncidentAction` model (differentiated by `action_type`).

This plan implements:
- **FIR-33**: `/ff actions` and `/ff followups` — separate list modals
- **FIR-34**: "Create action" and "Create follow-up" — separate create modals
- **FIR-35**: "I can take this" button for pickup, "Mark as done" for completion (shared for both types)
- **FIR-36**: 💥 reaction creates action, ▶️ reaction creates follow-up

---

## Step 1: Identifiers

**File**: `app/models/identifiers.rb`

```ruby
# Action modals
INCIDENT_ACTIONS_MODAL = "incident_actions_modal"
INCIDENT_FOLLOWUPS_MODAL = "incident_followups_modal"
CREATE_ACTION_MODAL = "create_action_modal"
CREATE_FOLLOWUP_MODAL = "create_followup_modal"

# Action buttons (shared for both types)
PICK_UP_ACTION = "pick_up_action"
MARK_ACTION_DONE = "mark_action_done"

# List modal buttons
ADD_NEW_ACTION = "add_new_action"
ADD_NEW_FOLLOWUP = "add_new_followup"

# Reaction buttons
CREATE_ACTION_FROM_REACTION = "create_action_from_reaction"
CREATE_FOLLOWUP_FROM_REACTION = "create_followup_from_reaction"
```

---

## Step 2: Slack Client — New API Methods

**File**: `app/adapters/slack/client.rb`

- `get_permalink(workspace:, channel:, message_ts:)` — calls `chat.getPermalink`, returns `{ permalink: }`. Needed for FIR-36 to link back to the reacted message.
- `get_message(workspace:, channel:, ts:)` — calls `conversations.history` with `latest: ts, limit: 1, inclusive: true`, returns the message hash. Needed for FIR-36 to fetch the reacted message text.

---

## Step 3: Modal Builder

**File**: `app/adapters/slack/modal_builder.rb`

### `actions_list_modal(incident)`
- callback_id: `INCIDENT_ACTIONS_MODAL`
- Title: "Actions"
- "+ Add new action" button (`ADD_NEW_ACTION`, value: incident.id)
- List of active actions (description, assignee, status)
- Empty state: "There aren't any actions yet"
- close: "Done", no submit button

### `followups_list_modal(incident)`
- callback_id: `INCIDENT_FOLLOWUPS_MODAL`
- Title: "Follow-ups"
- "+ Add new follow-up" button (`ADD_NEW_FOLLOWUP`, value: incident.id)
- List of active follow-ups
- Empty state: "There aren't any follow-ups yet"
- close: "Done", no submit button

### `create_action_modal(incident, private_metadata: nil)`
- callback_id: `CREATE_ACTION_MODAL`
- Title: "Create action"
- Fields: Description (required), Assignee (optional users_select "Who's picking it up?")
- Hint: "You can create an action from a Slack message by reacting with the 💥 emoji"
- submit: "Create", close: "Cancel"

### `create_followup_modal(incident, private_metadata: nil)`
- callback_id: `CREATE_FOLLOWUP_MODAL`
- Title: "Create follow-up"
- Fields: Description (required), Assignee (optional users_select "Who's picking it up?")
- Hint: "You can create a follow-up from a Slack message by reacting with the ▶️ emoji"
- submit: "Create", close: "Cancel"

---

## Step 4: Message Builder

**File**: `app/adapters/slack/incident_message_builder.rb`

### `action_created_blocks(action)`
```
<@CreatedBy> added an action:
[Description]
[👍 I can take this] button (if unassigned)
or
Assigned to: <@Assignee> (if assigned)
```

### `action_picked_up_blocks(action)`
```
<@CreatedBy> added an action:
[Description]
Picked up by: <@Assignee>
[✅ Mark as done] button
```

### `action_completed_blocks(action)`
```
<@CreatedBy> added an action:
~[Description]~
✅ Completed by <@Assignee>
```

All three methods use `action.action_type` to display "an action" vs "a follow-up" in the text.

### `action_from_reaction_blocks(action_type, message_text, incident_id, source_message_link)`
For actions (💥):
```
Should we create an action from this message?
> [truncated message preview]
[Yes, create action] [No thanks]
```

For follow-ups (▶️):
```
Should we create a follow-up from this message?
> [truncated message preview]
[▶️ Yes, create follow-up] [No thanks]
```

---

## Step 5: Adapter — High-Level Methods

**File**: `app/adapters/slack/workspace_adapter.rb`

- `open_actions_list_modal(trigger_id:, incident:)`
- `open_followups_list_modal(trigger_id:, incident:)`
- `open_create_action_modal(trigger_id:, incident:, private_metadata: nil)`
- `open_create_followup_modal(trigger_id:, incident:, private_metadata: nil)`
- `post_action_message(channel_id:, action:)` — posts action_created_blocks
- `update_action_message(channel_id:, ts:, action:, blocks:)` — updates message
- `get_message_permalink(channel_id:, message_ts:)` — calls Client.get_permalink
- `get_message(channel_id:, ts:)` — calls Client.get_message
- `post_action_from_reaction_prompt(channel_id:, user_id:, action_type:, message_text:, incident_id:, source_message_link:)` — posts ephemeral

---

## Step 6: IncidentActionService

**File**: `app/services/incident_action_service.rb` (new)

- `create_action(incident:, created_by:, action_type:, description:, assignee:, platform_data:)`
- `pick_up_action(action:, picked_up_by:)`
- `complete_action(action:, completed_by:)`

---

## Step 7: Commands

**File**: `app/services/commands/firefight/actions_handler.rb` (new)
- `/ff actions` or `/ff action` → opens Actions list modal

**File**: `app/services/commands/firefight/followups_handler.rb` (new)
- `/ff followups` or `/ff followup` → opens Follow-ups list modal

**Wire in** `app/services/commands/firefight/home_handler.rb`:
- `when "action", "actions"` → `ActionsHandler.execute(command)`
- `when "followup", "followups"` → `FollowupsHandler.execute(command)`

---

## Step 8: Interaction Handlers

### AddNewActionHandler
- `ADD_NEW_ACTION` block_action → opens create action modal

### AddNewFollowupHandler
- `ADD_NEW_FOLLOWUP` block_action → opens create follow-up modal

### CreateActionHandler
- `CREATE_ACTION_MODAL` view_submission → creates action via service

### CreateFollowupHandler
- `CREATE_FOLLOWUP_MODAL` view_submission → creates follow-up via service

### PickUpActionHandler (shared)
- `PICK_UP_ACTION` block_action → assigns action via service

### MarkActionDoneHandler (shared)
- `MARK_ACTION_DONE` block_action → completes action via service

### CreateActionFromReactionHandler
- `CREATE_ACTION_FROM_REACTION` block_action → opens pre-filled create action modal

### CreateFollowupFromReactionHandler
- `CREATE_FOLLOWUP_FROM_REACTION` block_action → opens pre-filled create follow-up modal

---

## Step 9: Wire Dispatchers

**File**: `app/services/interaction_dispatcher.rb`

VIEW_SUBMISSION_HANDLERS:
```ruby
Identifiers::CREATE_ACTION_MODAL => Interactions::CreateActionHandler,
Identifiers::CREATE_FOLLOWUP_MODAL => Interactions::CreateFollowupHandler
```

BLOCK_ACTION_HANDLERS:
```ruby
Identifiers::PICK_UP_ACTION => Interactions::PickUpActionHandler,
Identifiers::MARK_ACTION_DONE => Interactions::MarkActionDoneHandler,
Identifiers::ADD_NEW_ACTION => Interactions::AddNewActionHandler,
Identifiers::ADD_NEW_FOLLOWUP => Interactions::AddNewFollowupHandler,
Identifiers::CREATE_ACTION_FROM_REACTION => Interactions::CreateActionFromReactionHandler,
Identifiers::CREATE_FOLLOWUP_FROM_REACTION => Interactions::CreateFollowupFromReactionHandler
```

---

## Step 10: Events Controller & Reaction Handling (FIR-36)

### Events Controller
**File**: `app/controllers/api/v1/events_controller.rb` (new)

Handles Slack Events API:
1. `url_verification` → responds with `{ challenge: params[:challenge] }`
2. `event_callback` → enqueues `ProcessEventJob`

### Route
Add `post "events", to: "events#create"` in `api/v1` namespace

### ProcessEventJob
**File**: `app/jobs/process_event_job.rb` (new)

### EventDispatcher
**File**: `app/services/event_dispatcher.rb` (new) — routes `reaction_added` to handler

### ReactionAddedHandler
**File**: `app/services/events/reaction_added_handler.rb` (new)

Two-step flow (Events API has no trigger_id):
1. User reacts with 💥 or ▶️ on a message in incident channel
2. Handler checks emoji, finds incident, fetches message text + permalink
3. Posts ephemeral prompt: "Should we create an action/follow-up from this message?" with buttons
4. User clicks button → gets trigger_id → opens pre-filled create modal

---

## Implementation Order

1. Identifiers
2. Slack Client methods (get_permalink, get_message)
3. Modal Builder (4 modals)
4. Message Builder (action blocks + reaction prompt)
5. Adapter high-level methods
6. IncidentActionService
7. Command handlers (ActionsHandler, FollowupsHandler) + wire HomeHandler
8. Interaction handlers (all 8)
9. Wire dispatchers
10. Events controller + route + ProcessEventJob + EventDispatcher + ReactionAddedHandler
11. Tests
12. Run `bin/ci`
