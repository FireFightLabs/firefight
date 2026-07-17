# Firefight

Incident management platform built with Rails 8.1. Currently integrates with Slack, designed for multi-platform support (Teams, etc.).

## CI

Run `bin/ci` to validate changes. It runs rubocop, bundler-audit, brakeman, rails test (parallel), system tests, and seeds.

## Deep Dives

Detailed docs live in `docs/`. Read the relevant one **before** working in that area:

| Doc | Read when |
|---|---|
| [docs/architecture.md](docs/architecture.md) | Touching controllers, dispatchers, handlers, services, adapters, domain events, Slack events, outbound webhooks, or entitlements; adding a command, interaction, or entry point; deciding sync vs job |
| [docs/frontend.md](docs/frontend.md) | Any work under `app/frontend/` or on serializers (Inertia props, TS type generation, page/component structure, dashboard pattern) |
| [docs/workflows.md](docs/workflows.md) | Creating or modifying a workflow, or touching the SolidWorkflow engine (`engines/solid_workflow/`) |
| [docs/api.md](docs/api.md) | Working on the public REST API (`/api/v1/`), API keys, auth, or idempotency |
| [docs/mcp.md](docs/mcp.md) | Working on the MCP server (`/mcp`, `app/mcp/`), its tools, or agent-facing auth |
| [docs/ai.md](docs/ai.md) | AI features (`engines/firefight_ai/`), the Inference ledger, transcript store/scrubbing, or model configuration |

## Code Style

- No unnecessary comments — only explain non-obvious logic
- No ticket numbers in comments
- No emojis unless requested
- No direct `Rails.logger` helper wrappers — call `Rails.logger.info(...)` inline where needed
- Keep it simple, avoid over-engineering
- Rubocop enforced: `[ {...} ]` not `[{...}]` (SpaceInsideArrayLiteralBrackets)
- Never use raw strings for identifiers, resource names, action names, or event types — always use constants (e.g., `ApiKey::RESOURCE_INCIDENTS` not `"incidents"`, `IncidentEvent::INCIDENT_CREATED` not `"incident.created"`, `Identifiers::INCIDENT_CREATION_MODAL` not the string)
- Model concerns live next to their model in `app/models/<model>/`, not in `app/models/concerns/`. E.g. `Incident::Lifecycle` lives at `app/models/incident/lifecycle.rb`. Don't use `rails g concern` (it generates into `app/models/concerns/`) — create the file manually in the right directory.

## Architecture Rules (always apply)

```
Controller → Dispatcher → Handler → Service → Adapter → Slack::Client
                                  ↘ Job → Service → Adapter → Slack::Client   (heavy work only)
```

- Each layer has a single responsibility. **Never skip layers.**
- **`app/services/` is ONLY for cross-platform orchestration** — code that coordinates model writes with adapter calls, workflow starts, cache expiry, or job scheduling. **Pure domain logic that only touches a model's own data is a model method or a concern in `app/models/<model>/` — never a service.** Litmus test before creating anything in `app/services/`: does it call an adapter, start a workflow, or touch another system? If no, it belongs on the model (e.g. `Policy::Evaluation` concern, not a `PolicyRouter` service; `Postmortem#update_content!`, not a `PostmortemUpdateService`).
- Slack and the Public API are thin **entry points** into the same system — business logic and side effects live in shared services, never in entry points. All incident writes go through `IncidentLifecycleService`.
- Handlers are thin (guards, routing, delegation) and stateless. No DB queries beyond `command.workspace`/`command.incident`, no Block Kit, no business logic.
- Commands dispatch synchronously; a handler enqueues its own job only for heavy work (AI calls, paginated Slack lookups, >~1.5s). Anything opening a modal must stay sync — `trigger_id` expires in 3s.
- All platform calls go through `WorkspaceAdapter.for(workspace)`; `Slack::Client` is only called from `Slack::WorkspaceAdapter`. No Slack-specific code outside `app/adapters/slack/`. Rescue `AdapterError` subclasses, never platform errors.
- Meaningful state changes to `Incident`/`IncidentAction`/`Postmortem` go through `record_change!` (Trackable/Recordable) so the snapshot + event are written together.
- All callback_ids, action_ids, and subcommand strings come from the `Identifiers` module — never magic strings.

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
