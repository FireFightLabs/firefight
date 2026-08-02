# Firefight

Incident management platform built with Rails 8.1. Currently integrates with Slack, designed for multi-platform support (Teams, etc.).

## CI

Run `bin/ci` to validate changes. It runs rubocop, bundler-audit, brakeman, rails test (parallel), system tests, and seeds.

## Git & PRs

- **Never merge a PR without an explicit instruction to merge in the current message.** Opening PRs when asked to build something is fine; merging is always the user's call, every time — prior merge approvals and inferred intent (e.g. a bug report that a feature "isn't working") do not count.

## Documentation (always applies)

Product docs live in a separate repo, `../firefight-landing`, and are served at `firefight.app/docs`. They are part of the change, not a follow-up.

- **Any change a user can see requires a matching docs update.** New or changed `/ff` commands, dialogs, settings screens, API endpoints, MCP tools, webhook events, or renamed navigation. A feature that ships undocumented is half-shipped.
- **`../firefight-landing/CLAUDE.md` owns how docs are written** — audience, voice, punctuation, page shape, sidebar wiring. Read it before touching `src/content/docs/`, and follow it over any instinct carried across from this repo.
- **Docs ship as their own PR** in that repo, opened alongside the code PR here, with the code PR naming it.
- Repo-internal docs under `docs/` are engineering references and a separate obligation: update the relevant one in the same PR as the code.
- If a change turns out to need no docs update, say so explicitly rather than leaving it unmentioned.

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

## Settings screen UX standards (always apply)

Every settings list behaves the same way. A new one joins this pattern rather than inventing its own.

- **Every mutating action confirms itself with a toast.** Create, update, delete, enable, disable, reorder, set-default. An action that succeeds silently is indistinguishable from one that failed. `redirect_to ..., notice:` is enough, `FlashToaster` renders it.
- **Delete asks first, via `ConfirmDeleteDialog`.** Never `router.delete` straight from a row. The description says what is lost, and names it: how many deliveries, how many incidents.
- **Delete only at zero references, disable otherwise.** Above zero the Delete item stays visible but inert, with a tooltip naming the exact count. Never hide the control, and never let it fail silently.
- **Guard rules live on the model as `*_blocked_reason`**, returning a sentence or nil. Controller turns it into a flash alert, serializer ships it, row renders it as a tooltip. Never re-derive a rule in the controller or the frontend, and never ship a bare `deletable` boolean: it drifts from what the controller enforces.
- **Soft delete requires a way back.** If `destroy` sets `deleted_at`, the screen must list disabled rows and offer enable. A row that vanishes while still holding its slug is unreachable, not deleted.
- **Reorder is optimistic.** The row moves on drop and stays; the request goes out immediately and only a failure reverts it. Use `useOptimisticOrder`. Never make the user watch rows snap back while a request is in flight.
- **Counts come from one subquery**, `with_usage_counts`, never a `count` or `exists?` per row.
- **Descriptions are stored as finished sentences.** Any model with a user-entered `description` that reaches Slack includes `NormalizedDescription`, which capitalizes an all-lowercase first word and terminates the sentence on save. Slack silently appends a period to `hint` text when one is missing, so an unnormalized description renders differently in Slack than in the dashboard. Normalize on save, never at render, or each surface drifts on its own. Seeded defaults are written already normalized so the constant matches what is stored.
- **Reuse the shared pieces**: `OptionsTable`, `SortableOptionRow`, `OptionDialog` (owns both create and edit), `ConfirmDeleteDialog`, `RowActions`, `ColorPicker`. Model side: `OptionGuards` for usage and blocked reasons, `ConfigurableOption` when the list is also positioned and slugged, `DefaultableOption` when one row is the workspace default, `NormalizedDescription` when the row has a description.

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
- User-facing copy (UI strings, labels, descriptions, tooltips, flash messages, seeded descriptions, product docs on the marketing and docs sites) uses **no em dashes and no semicolons at all**. Not "no unnecessary semicolons" — none. Write two sentences, or use a comma or parenthesis. This covers seeds, migrations that insert copy, and fixtures, not just `.tsx`. Empty table cells use a plain hyphen, not a dash glyph.
- Exempt from the dash rule: **titles using a dash as a separator** (`<Head title>`, Slack message headers: `INC-052 — Checkout failing`), engineering docs under `docs/`, code comments, exception and log messages, and machine-facing schema text such as MCP tool parameter descriptions.
- No direct `Rails.logger` helper wrappers — call `Rails.logger.info(...)` inline where needed
- Keep it simple, avoid over-engineering
- Rubocop enforced: `[ {...} ]` not `[{...}]` (SpaceInsideArrayLiteralBrackets)
- **Braces on every `if` body in TypeScript**, even a one-liner and including early-exit guards. Enforced by eslint `curly: ["error", "all"]`, so `npm run lint` fails on a bare `if (x) doThing()`. `--fix` collapses the body onto one line (`{return}`), which is not the house style: expand it to a real block.
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
