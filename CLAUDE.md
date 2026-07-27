# Firefight

Incident management platform built with Rails 8.1. Currently integrates with Slack, designed for multi-platform support (Teams, etc.).

## CI

Run `bin/ci` to validate changes. It runs rubocop, bundler-audit, brakeman, rails test (parallel), system tests, and seeds.

## Git & PRs

- **Never merge a PR without an explicit instruction to merge in the current message.** Opening PRs when asked to build something is fine; merging is always the user's call, every time — prior merge approvals and inferred intent (e.g. a bug report that a feature "isn't working") do not count.

## No shortcuts (always applies)

Production-grade or not at all. Every one of these has already been violated once; none is hypothetical.

- **Never ship a placeholder interaction.** No `window.prompt` / `confirm` / `alert`, no unstyled control, no "fine for now" input. If a flow needs input it gets the same dialog treatment as every other flow in the app. There is no such thing as an incidental piece of UI — the throwaway bit is usually the first thing a user touches.
- **Reuse the existing pattern before inventing one.** Find the nearest component already in `app/frontend/` and match it. Introducing a new interaction pattern is a decision to state out loud, never a side effect of moving fast.
- **If the model supports N, the UI must not assume 1.** Rendering `records.find(...)` where the schema permits many silently hides rows. Check the second case: the second connection, the second credential set, the already-connected state, the empty list.
- **A capability that cannot be reached does not exist.** Model plus controller plus serializer is half the job. Before calling a feature done, name the click path to it from a cold page, including for the state *after* the first one (already connected, already granted).
- **Green CI is not evidence the UI works.** `bin/ci` and `tsc` never render a pixel. Look at the page, or say plainly that you did not.
- **Generated files are part of the change.** Adding a route means `bin/rails js:routes:typescript`; adding or editing a serializer means `bundle exec rake types_from_serializers:generate`. Forgetting either breaks the app at import time, not at test time.
- **Never silence a linter or type checker.** No `eslint-disable`, `rubocop:disable`, `@ts-ignore`, `@ts-expect-error`, `as any`, or `as unknown as`. The rule is pointing at a real problem, so fix the code it points at. `react-hooks/exhaustive-deps` firing on a mount-only effect means the effect is reading something it claims not to depend on — capture it in a ref or restructure. If a suppression is genuinely the only option, say so out loud and explain why in the same message, never quietly in a comment.
- **`bin/ci` does not check the frontend.** No eslint, no `tsc`. Run `npm run lint` and `npx tsc --noEmit` yourself before calling frontend work done; green `bin/ci` says nothing about it.
- **Finish the whole path, or say exactly what you left undone.** Deferring part of a task is fine when it is stated. Silence reads as complete, which makes it a false claim.

## Deep Dives

Detailed docs live in `docs/`. Read the relevant one **before** working in that area:

| Doc | Read when |
|---|---|
| [docs/architecture.md](docs/architecture.md) | Touching controllers, dispatchers, handlers, services, adapters, domain events, Slack events, outbound webhooks, or entitlements; adding a command, interaction, or entry point; deciding sync vs job |
| [docs/frontend.md](docs/frontend.md) | Any work under `app/frontend/` or on serializers (Inertia props, TS type generation, page/component structure, dashboard pattern) |
| [docs/workflows.md](docs/workflows.md) | Creating or modifying a workflow, or touching the SolidWorkflow engine (`engines/solid_workflow/`) |
| [docs/api.md](docs/api.md) | Working on the public REST API (`/api/v1/`), API keys, auth, or idempotency |
| [docs/mcp.md](docs/mcp.md) | Working on the MCP server (`/mcp`, `app/mcp/`), its tools, or agent-facing auth |
| [docs/integrations.md](docs/integrations.md) | Adding or changing an integration provider or connection, and anything touching the Ability Gateway (actions, grants, approvals, the invocation ledger) |
| [docs/ai.md](docs/ai.md) | AI features (`engines/firefight_ai/`), the Inference ledger, transcript store/scrubbing, or model configuration |

## Code Style

- No unnecessary comments — only explain non-obvious logic
- No ticket numbers in comments
- No emojis unless requested
- User-facing copy (UI strings, labels, descriptions, tooltips, flash messages, seeded descriptions, product docs on the marketing and docs sites) uses **no em dashes and no semicolons at all**. Not "no unnecessary semicolons" — none. Write two sentences, or use a comma or parenthesis. This covers seeds, migrations that insert copy, and fixtures, not just `.tsx`. Empty table cells use a plain hyphen, not a dash glyph. Engineering docs under `docs/` and code comments are exempt.
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
- Every privileged operation goes through `AbilityGateway.authorize!` — never check permissions inline. **Config ≠ permission**: a grant and a wired `IntegrationEnvironment` are both required, and the gateway asks `action.configured_for?(scope)` rather than reaching into the integrations layer.
- Machines never inherit a human's reach: service keys and `Agent` principals hold only explicit grants, whatever their creator can do.
- Adding an integration provider is an entry in `config/integration_providers.yml` plus env vars, never new code. Discovered tools arrive disabled; enabling one mints exactly one action.
- Secrets never enter the session, an MCP tool response, or the ledger. Credential shapes are owned by `Integrations::OauthClient`; only `IntegrationEnvironment` persists them.

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
