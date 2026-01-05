# Slash Command Request Flow

Visual guide showing exactly how a `/firefight` command flows through the system.

## End-to-End Flow

```
User types: /firefight
     ↓
Slack sends POST request to /api/v1/commands
     ↓
[Api::V1::CommandsController#create]
     │
     ├─→ Slack::SignatureVerifier.verify!(request)
     │   └─→ Verifies HMAC signature + timestamp
     │       └─→ Raises error if invalid (returns 401)
     │
     ├─→ Find workspace by team_id
     │   └─→ Returns 404 if not found
     │
     ├─→ ProcessCommandJob.perform_later("slack", params)
     │   └─→ Enqueued to Solid Queue
     │
     └─→ Render { ok: true } (< 100ms)

─────────────────────────────────────────────────

[ProcessCommandJob] (runs in background, < 3s)
     │
     ├─→ Slack::CommandAdapter.parse(payload)
     │   └─→ Returns Command object:
     │       {
     │         platform: "slack",
     │         workspace_id: "uuid",
     │         user_id: "U123",
     │         text: "",
     │         trigger_id: "123.456.abc",
     │         channel_id: "C789",
     │         metadata: {...}
     │       }
     │
     ├─→ CommandDispatcher.find(command)
     │   └─→ Check command.text:
     │       • Empty → ModalHandler
     │       • "help" → HelpHandler
     │       • "status" → StatusHandler
     │       • other → ModalHandler (default)
     │
     └─→ Commands::ModalHandler.execute(command)

─────────────────────────────────────────────────

[Commands::ModalHandler]
     │
     ├─→ Fetch workspace from database
     │
     ├─→ Slack::ModalBuilder.incident_creation_form
     │   └─→ Returns Block Kit JSON:
     │       {
     │         type: "modal",
     │         blocks: [
     │           { title input },
     │           { description textarea },
     │           { severity dropdown }
     │         ]
     │       }
     │
     ├─→ Slack::Client.open_modal(
     │       workspace: workspace,
     │       trigger_id: command.trigger_id,
     │       view: modal_view
     │   )
     │   │
     │   └─→ POST https://slack.com/api/views.open
     │       Headers: { Authorization: "Bearer {workspace.access_token}" }
     │       Body: { trigger_id: "...", view: {...} }
     │       │
     │       └─→ Slack API response:
     │           • Success: { ok: true, view: {...} }
     │           • Trigger expired: { ok: false, error: "expired_trigger_id" }
     │           • Other error: { ok: false, error: "..." }
     │
     └─→ If trigger expired:
         └─→ Slack::Client.post_ephemeral(
                 workspace: workspace,
                 channel: command.channel_id,
                 user: command.user_id,
                 text: "⏰ Command timed out. Try again."
             )

─────────────────────────────────────────────────

Modal appears in Slack UI
     ↓
User fills form and clicks "Create"
     ↓
Slack sends POST request to /api/v1/interactions
     ↓
[Api::V1::InteractionsController#create]
     │
     ├─→ Slack::SignatureVerifier.verify!(request)
     │
     ├─→ Parse JSON payload from params[:payload]
     │   └─→ {
     │         type: "view_submission",
     │         view: {
     │           callback_id: "incident_creation_modal",
     │           state: {
     │             values: {
     │               title_block: { title_input: { value: "..." } },
     │               description_block: { description_input: { value: "..." } },
     │               severity_block: { severity_select: { selected_option: {...} } }
     │             }
     │           }
     │         }
     │       }
     │
     ├─→ handle_view_submission(payload)
     │   └─→ Currently just logs the submission
     │       TODO: Create incident, trigger workflows, etc.
     │
     └─→ Render { ok: true }
         └─→ Modal closes in Slack

─────────────────────────────────────────────────

Future: Incident Creation (not implemented yet)
     │
     ├─→ Parse form values from payload
     │
     ├─→ Create Incident record
     │
     ├─→ Trigger IncidentCreationWorkflow
     │   ├─→ Step 1: Create Slack channel
     │   ├─→ Step 2: Post initial message
     │   ├─→ Step 3: Invite on-call team
     │   └─→ Step 4: Send notifications
     │
     └─→ Post confirmation to Slack
```

## Timing Constraints

### Critical: Trigger ID Expiration

Slack's `trigger_id` expires **3 seconds** after the slash command is issued.

```
T+0s:   User types /firefight
        Slack generates trigger_id
        ↓
T+0.05s: API receives request
         Enqueues ProcessCommandJob
         Returns 200 OK
         ↓
T+0.5s:  Job starts processing
         Parses command
         Calls ModalHandler
         ↓
T+1.5s:  Slack::Client.open_modal called
         trigger_id still valid ✅
         ↓
T+2.0s:  Modal appears in Slack

─────────────────────────────────────

If job is delayed:

T+0s:   User types /firefight
        ↓
T+4s:   Job finally runs (too slow!)
        Calls open_modal with expired trigger_id ❌
        ↓
        Slack API returns: { ok: false, error: "expired_trigger_id" }
        ↓
        Fallback: Post ephemeral message
        "⏰ Command timed out. Try again."
```

### Performance Targets

- **Controller response:** < 100ms
- **Job execution:** < 2s (leaves 1s buffer)
- **Total time to modal:** < 3s

## Platform Abstraction

The system is designed so Slack-specific code is isolated:

```
┌─────────────────────────────────────────┐
│        Platform-Agnostic Core           │
│                                         │
│  • Command (PORO)                       │
│  • CommandDispatcher                    │
│  • Commands::*Handler                   │
│                                         │
│  No knowledge of Slack/Teams!           │
└─────────────────────────────────────────┘
            ↑               ↑
            │               │
    ┌───────┴────┐    ┌────┴────────┐
    │   Slack    │    │   Teams     │
    │  Adapter   │    │   Adapter   │
    │            │    │             │
    │  • Parse   │    │  • Parse    │
    │  • Build   │    │  • Build    │
    │  • Client  │    │  • Client   │
    └────────────┘    └─────────────┘
```

## Adding a New Command

Example: Add `/firefight status` to show incident status

### 1. Create Handler

```ruby
# app/services/commands/status_handler.rb
module Commands
  class StatusHandler
    def self.execute(command)
      workspace = command.workspace

      # Fetch recent incidents (not implemented yet)
      # incidents = Incident.where(workspace: workspace).recent

      # Build message
      message = "📊 *Incident Status*\n\n"
      message += "No active incidents"

      # Post to Slack
      Slack::Client.post_ephemeral(
        workspace: workspace,
        channel: command.channel_id,
        user: command.user_id,
        text: message
      )
    end
  end
end
```

### 2. Update Dispatcher

```ruby
# app/services/command_dispatcher.rb
def self.find(command)
  case command.subcommand&.downcase
  when "status", "s"
    Commands::StatusHandler  # Add this
  when "help", "h"
    Commands::HelpHandler
  # ...
  end
end
```

### 3. Test

```
/firefight status
→ Shows incident status in ephemeral message
```

## Security Layers

### Request Verification Flow

```
Slack Request
     ↓
┌────────────────────────────────────┐
│ 1. Signature Verification         │
│                                    │
│ Headers:                           │
│ X-Slack-Request-Timestamp: 1234... │
│ X-Slack-Signature: v0=abc123...    │
│                                    │
│ Verify:                            │
│ • Timestamp < 5 min old            │
│ • HMAC-SHA256 matches              │
│   using signing_secret             │
└────────────────────────────────────┘
     ↓ (raises error if invalid)
┌────────────────────────────────────┐
│ 2. Workspace Validation            │
│                                    │
│ • Find by team_id                  │
│ • Ensure installed                 │
│ • Has valid access token           │
└────────────────────────────────────┘
     ↓ (404 if not found)
┌────────────────────────────────────┐
│ 3. Process Command                 │
│                                    │
│ • Enqueue background job           │
│ • Return 200 OK                    │
└────────────────────────────────────┘
```

### What's NOT Needed

❌ **Session cookies** - Not API endpoints
❌ **CSRF tokens** - Signature verification instead
❌ **API keys** - Slack signature is proof of origin
❌ **Rate limiting** - (not yet, but should add later)

## Error Handling

### Graceful Degradation

```ruby
begin
  Slack::Client.open_modal(...)
rescue Slack::Client::TriggerExpiredError
  # Trigger ID expired (>3s)
  # → Post ephemeral message instead
  Slack::Client.post_ephemeral(
    text: "⏰ Command timed out. Try again."
  )
rescue Slack::Client::ApiError => e
  # Other Slack API error
  # → Notify user, log error
  Rails.logger.error("Slack API error: #{e}")
  Slack::Client.post_ephemeral(
    text: "❌ Something went wrong. Try again."
  )
end
```

### User-Friendly Errors

Instead of:
```
500 Internal Server Error
```

Users see:
```
⏰ The command timed out. Please try /firefight again.
```

Or:
```
❌ Sorry, something went wrong. Please try again.
```

## Monitoring Points

Good places to add monitoring/metrics:

1. **Command received** - Count by type, workspace
2. **Job execution time** - Alert if > 2s
3. **Modal open success/failure** - Track trigger_id expiration rate
4. **API errors** - Track Slack API failures
5. **Signature verification failures** - Potential security issue

Example with Rails instrumentation:

```ruby
ActiveSupport::Notifications.instrument(
  "command.received",
  command: command.subcommand,
  workspace: workspace.name
) do
  CommandDispatcher.dispatch(command)
end
```
