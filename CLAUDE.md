# Firefight

Incident management platform built with Rails 8.1. Currently integrates with Slack, designed for multi-platform support (Teams, etc.).

## CI

Run `bin/ci` to validate changes. It runs rubocop, bundler-audit, brakeman, rails test (parallel), system tests, and seeds.

## Code Style

- No unnecessary comments — only explain non-obvious logic
- No ticket numbers in comments
- No emojis unless requested
- No direct `Rails.logger` helper wrappers — call `Rails.logger.info(...)` inline where needed
- Keep it simple, avoid over-engineering
- Rubocop enforced: `[ {...} ]` not `[{...}]` (SpaceInsideArrayLiteralBrackets)

## Architecture

### Layer Hierarchy

```
Controller → Job → Dispatcher → Handler → Service → Adapter → Slack::Client
```

Each layer has a single responsibility. Never skip layers.

### Thin Controllers

Controllers validate requests, enqueue jobs, and respond immediately. No business logic. Slack requires response within 3 seconds (trigger_id expiration).

```
Api::V1::CommandsController → ProcessCommandJob.perform_later → head :ok
Api::V1::InteractionsController → InteractionDispatcher.dispatch (sync, needs response body for modals)
```

### Dispatchers

Route to handlers using lookup tables. Fall back to `UnknownHandler`.

- `CommandDispatcher` — routes on `command.command_name` + `command.subcommand`
- `InteractionDispatcher` — routes on `interaction.type` + `callback_id`/`action_id`

### Handlers

Class methods with `self.execute(command)` or `self.execute(interaction)`. Stateless. Return response hashes or nil.

### Normalizers

Platform-specific payloads are normalized into platform-agnostic POJOs before reaching handlers.

- `Slack::CommandAdapter.parse(payload)` → `Command` (ActiveModel with validations)
- `Slack::InteractionNormalizer.call(payload)` → `Interaction` (plain PORO with attr_readers)

Handlers access normalized fields (`interaction.user_id`, `command.trigger_id`) — never dig into raw payloads.

### Services

Encapsulate business logic. Each method is independently callable (from workflows, console, or controllers). Use adapters for platform operations.

- `WorkspaceSetupService` — workspace setup flow
- `IncidentCreationService` — incident creation flow

Pattern:
```ruby
adapter = WorkspaceAdapter.for(workspace)
adapter.create_channel(name: ..., is_private: ...)
```

### Adapters

Platform abstraction layer. `WorkspaceAdapter.for(workspace)` is the factory — returns platform-specific adapter (e.g., `Slack::WorkspaceAdapter`).

Adapters catch platform-specific errors and re-raise as `AdapterError` subclasses:
- `Slack::Client::TriggerExpiredError` → `AdapterError::TriggerExpired`
- `Slack::Client::ChannelExistsError` → `AdapterError::ChannelExists`

Services and handlers rescue `AdapterError` subclasses — never platform-specific errors.

Adapters return normalized hashes: `{ channel_id:, channel_name: }`, `{ message_ts: }`, `{ success: true }`.

### Workflows

Thin orchestrators using a `step` DSL with dependency declarations. Delegate all logic to services.

```ruby
class IncidentCreationWorkflow < Base
  step :create_slack_channel
  step :set_channel_metadata, depends_on: [:create_slack_channel]

  def create_slack_channel(workflow:, step:, input:)
    service(workflow).create_channel(workflow.subject)
  end
end
```

- `start!(subject)` — async via background jobs
- `start_inline!(subject)` — synchronous (tests/console)

### Slack Identifiers

All callback_ids and action_ids are centralized in `Slack::Identifiers`. Never use magic strings for Slack identifiers.

## Key Files

```
app/adapters/
  adapter_error.rb                    # Platform-agnostic error hierarchy
  workspace_adapter.rb                # Factory: WorkspaceAdapter.for(workspace)
  slack/
    client.rb                         # Slack API wrapper (HTTParty)
    workspace_adapter.rb              # Slack adapter implementation
    identifiers.rb                    # All Slack callback_ids/action_ids
    interaction_normalizer.rb         # Raw payload → Interaction POJO
    command_adapter.rb                # Raw payload → Command POJO
    modal_builder.rb                  # Block Kit modal definitions
    incident_message_builder.rb       # Incident-related Block Kit messages

app/models/
  command.rb                          # Platform-agnostic command (ActiveModel)
  interaction.rb                      # Platform-agnostic interaction (PORO)
  incident.rb                         # AR model with concerns (Sequencing, ChannelNaming, etc.)

app/services/
  command_dispatcher.rb               # Routes commands → handlers
  interaction_dispatcher.rb           # Routes interactions → handlers
  workspace_setup_service.rb          # Workspace setup business logic
  incident_creation_service.rb        # Incident creation business logic

app/workflows/
  base.rb                             # Workflow engine with step DSL
  incident_creation_workflow.rb       # Thin delegates to IncidentCreationService
  slack_workspace_setup_workflow.rb   # Thin delegates to WorkspaceSetupService
```

## Testing

- Framework: Minitest + Mocha (mocking)
- Tests run in parallel (14 processes)
- **Never use `Model.last`** in tests — unreliable with parallel execution. Use `find_by!` with specific attributes or scoped queries like `@incident.incident_events.find_by!(event_type: ...)`
- Fixtures require careful FK loading: `workspace_memberships` needs `:users`
- Slack API stubs: `test/support/slack_client_stub_helper.rb` provides `stub_create_channel`, `stub_post_message`, `stub_successful_slack_workflow`, etc.
- Mocha auto-unstubs after each test — thread-safe isolation
- Handler tests build `Interaction.new(...)` or `Command` objects directly — never raw hashes
- Workflow tests use `start_inline!` for synchronous execution
- Use `Interaction::VIEW_SUBMISSION`, `Interaction::BLOCK_ACTIONS`, etc. — never raw type strings
