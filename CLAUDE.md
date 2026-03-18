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
Api::V1::InteractionsController → Slack::InteractionNormalizer.call → InteractionDispatcher.dispatch (sync, needs response body for modals)
```

Controllers are the platform-specific boundary — they normalize payloads into platform-agnostic objects before passing to dispatchers.

### Dispatchers

Route to handlers using lookup tables. Fall back to `UnknownHandler`.

- `CommandDispatcher` — routes on `command.command_name` + `command.subcommand`
- `InteractionDispatcher` — routes on `interaction.type` + `callback_id`/`action_id`

### Handlers

Class methods with `self.execute(command)` or `self.execute(interaction)`. Stateless. Return response hashes or nil.

Handlers are thin — only guards, routing, and delegation:
- Guard clauses (`return ephemeral("...") unless command.workspace`)
- Route to the right service or adapter method
- Return the response hash

Never put in a handler: DB queries beyond `command.workspace` / `command.incident`, business logic, platform-specific formatting (Block Kit, Slack mrkdwn), or response building. That belongs in services (business logic) or the adapter (platform-specific output).

`command.workspace` and `command.incident` are memoized on `Command` — call them directly, no local variable needed.

### Normalizers

Platform-specific payloads are normalized into platform-agnostic POJOs at the boundary (controllers/jobs) before reaching dispatchers and handlers.

- `Slack::CommandAdapter.parse(payload)` → `Command` (ActiveModel with validations) — called in `ProcessCommandJob`
- `Slack::InteractionNormalizer.call(payload)` → `Interaction` (plain PORO with attr_readers) — called in `InteractionsController`

Dispatchers and handlers only receive normalized objects — never raw payloads. Handlers access normalized fields (`interaction.user_id`, `command.trigger_id`).

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

Platform abstraction layer. `WorkspaceAdapter.for(workspace)` is the factory — returns platform-specific adapter (e.g., `Slack::WorkspaceAdapter`). Always use the factory, never instantiate platform adapters directly.

Adapters have two levels of methods:
- **Low-level**: generic operations (`post_message`, `open_modal`, `pin_message`, `post_ephemeral`)
- **High-level**: intent-based operations that encapsulate UI building (`open_incident_creation_modal`, `open_home_modal`, `update_home_modal`, `post_incident_quick_actions`, `post_incident_announcement`)

Handlers and services call high-level adapter methods — never reference platform-specific builders (`Slack::ModalBuilder`, `Slack::IncidentMessageBuilder`) directly. UI building stays inside the adapter layer.

Adapters catch platform-specific errors and re-raise as `AdapterError` subclasses:
- `Slack::Client::TriggerExpiredError` → `AdapterError::TriggerExpired`
- `Slack::Client::ChannelExistsError` → `AdapterError::ChannelExists`

Services and handlers rescue `AdapterError` subclasses — never platform-specific errors.

Adapters return normalized hashes: `{ channel_id:, channel_name: }`, `{ message_ts: }`, `{ success: true }`.

**Platform boundary rule**: `Slack::Client` is only called from `Slack::WorkspaceAdapter`. No Slack-specific code outside `app/adapters/slack/`.

### Domain Events

`IncidentEvent` records are created via `incident.record_change!` or `incident.create_initial_update!` (defined in `Incident::Snapshots`). Both return the created `IncidentEvent`.

Domain event publication (`ProcessDomainEventJob`) belongs in the **service layer**, not in model callbacks. Models must not enqueue jobs.

### Workflows

Built on the SolidWorkflow engine (`engines/solid_workflow/`). Thin orchestrators that delegate all logic to services.

#### Step DSL

```ruby
class IncidentCreationWorkflow < Base
  step :create_slack_channel
  step :set_channel_metadata, depends_on: [:create_slack_channel]
  step :notify, retry_config: { max_attempts: 3, backoff: "fixed" }

  def create_slack_channel(workflow:, step:, input:)
    service(workflow).create_channel(workflow.subject)
  end

  def set_channel_metadata(workflow:, step:, input:)
    channel_id = input["create_slack_channel"]["channel_id"]
    service(workflow).set_channel_metadata(workflow.subject, channel_id)
  end
end
```

- `step :name, depends_on: [...]` — declares a step with dependency ordering
- `step :name, retry_config: { max_attempts:, backoff: }` — per-step retry override
- Steps without dependencies run in parallel automatically
- Step methods receive `workflow:` (AR record, access `workflow.subject` and `workflow.context`), `step:` (AR record), `input:` (hash of dependency outputs keyed by step name)
- Return value becomes the step's `output` hash

#### Execution

- `start!(subject, context: {})` — async via background jobs (`RunStepJob`)
- `start_inline!(subject, context: {})` — synchronous (tests/console)
- Subject is a polymorphic AR object the workflow operates on

#### Orchestration

After each step completes, the engine finds newly ready steps (all dependencies succeeded/skipped, `run_at` passed) and enqueues them. Optimistic locking on `updated_at` prevents double execution of the same step.

#### States

- **Step**: `pending → running → succeeded/failed/skipped/cancelled`
- **Workflow**: `pending → running → succeeded/failed/cancelled/paused`

#### Retry

- Default: 5 attempts, exponential backoff (`2^attempt` seconds, capped at 300s)
- Strategies: `exponential` (default), `linear` (`attempt * 30s`), `fixed` (configurable or 60s)
- Per-step override via `retry_config: { max_attempts:, backoff:, backoff_seconds: }`

#### Pause / Resume / Cancel

- `workflow.pause!(reason:, by:)` — running steps finish, no new steps enqueued
- `workflow.resume!(by:)` — resumes orchestration
- `workflow.cancel!(reason:, by:)` — permanent, cancels all pending/running steps

#### Recovery

`SweeperJob` handles crashes: resumes stuck workflows (idle >5min), resets orphaned running steps (idle >10min), fails timed-out workflows.

#### Event Timeline

Every state transition records a `SolidWorkflow::Event` (workflow-level and step-level). `workflow.timeline` returns the chronological audit trail.

#### Key Engine Files

```
engines/solid_workflow/
  lib/solid_workflow/base.rb              # DSL (step, start!, start_inline!)
  lib/solid_workflow.rb                   # Module config (queue, retries, thresholds)
  app/models/solid_workflow/workflow.rb   # Workflow AR model + concerns
  app/models/solid_workflow/step.rb       # Step AR model + concerns
  app/models/solid_workflow/event.rb      # Audit trail events
  app/jobs/solid_workflow/run_step_job.rb # Executes a single step
  app/jobs/solid_workflow/sweeper_job.rb  # Recovers stuck/orphaned steps
```

### Identifiers

All callback_ids, action_ids, and subcommand strings are centralized in the platform-agnostic `Identifiers` module (`app/models/identifiers.rb`). Never use magic strings. Reference as `Identifiers::INCIDENT_CREATION_MODAL`, `Identifiers::SUBCOMMAND_CLOSE`, etc.

## Key Files

```
app/adapters/
  adapter_error.rb                    # Platform-agnostic error hierarchy
  workspace_adapter.rb                # Factory: WorkspaceAdapter.for(workspace)
  slack/
    client.rb                         # Slack API wrapper (HTTParty)
    workspace_adapter.rb              # Slack adapter (low-level + high-level methods)
    interaction_normalizer.rb         # Raw payload → Interaction POJO
    command_adapter.rb                # Raw payload → Command POJO
    modal_builder.rb                  # Block Kit modal definitions (internal to adapter)
    incident_message_builder.rb       # Incident Block Kit messages (internal to adapter)

app/models/
  command.rb                          # Platform-agnostic command (ActiveModel)
  interaction.rb                      # Platform-agnostic interaction (PORO, has platform attr)
  identifiers.rb                      # Platform-agnostic callback_ids/action_ids
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
- Fixtures require complete FK loading — declare all dependencies up the chain. `incidents` needs `:workspaces, :users, :workspace_memberships, :incident_statuses, :incident_severities, :incident_lifecycle_stages`. Missing fixtures cause random FK violations under parallel execution.
- Slack API stubs: `test/support/slack_client_stub_helper.rb` provides `stub_create_channel`, `stub_post_message`, `stub_successful_slack_workflow`, etc.
- Mocha auto-unstubs after each test — thread-safe isolation
- Handler tests build `Interaction.new(platform: Platforms::SLACK, ...)` or `Command` objects directly — never raw hashes
- Workflow tests use `start_inline!` for synchronous execution
- Use `Interaction::VIEW_SUBMISSION`, `Interaction::BLOCK_ACTIONS`, etc. — never raw type strings
- Use `Identifiers::INCIDENT_CREATION_MODAL`, etc. — never `Slack::Identifiers::`
