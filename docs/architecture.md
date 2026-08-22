# Architecture

Backend layering, entry points, services, adapters, and domain events. Read this before touching controllers, dispatchers, handlers, services, adapters, or domain events, or before adding a new entry point or command.

## Layer Hierarchy

```
Controller → Dispatcher → Handler → Service → Adapter → Slack::Client
                                  ↘ Job → Service → Adapter → Slack::Client   (heavy work only)
```

Each layer has a single responsibility. Never skip layers.

Commands dispatch **synchronously** by default — Slack's 3-second budget covers the common path (modal openers, ephemerals, fast DB work). A handler enqueues its own job only when the work can't fit: AI generation, paginated Slack lookups, large fan-outs. See [When to enqueue from a handler](#when-to-enqueue-from-a-handler).

## Entry Points (Boundary Layers)

Slack and the Public API are **entry points** into the same system. They are thin boundary layers that normalize platform-specific input and call shared services. All business logic and side effects live in shared services — never in entry points.

```
Slack:  Controller → Dispatcher → Handler → IncidentLifecycleService → Workflows
API:    Controller                        → IncidentLifecycleService → Workflows
Teams:  (future)   → ...                  → IncidentLifecycleService → Workflows
```

There is a third inbound path for Slack **events** (messages, reactions, pins, mentions) — see [Slack Events](#slack-events-third-entry-path) below. It follows the same boundary rules.

### What entry points do (boundary concerns only)
1. **Normalize input** — parse platform-specific payload into resolved records (Slack: dig into interaction values, resolve slugs; API: parse JSON params, resolve UUIDs)
2. **Call shared service** — `IncidentLifecycleService.new(workspace).create(...)` / `.update(...)` / `.close(...)` etc.
3. **Platform-specific response** — Slack: return modal hash, delete temp messages; API: render JSON
4. **Platform-specific extras** — only when the platform requires it (e.g., Slack handler creates channel synchronously before the workflow so the confirmation modal can include a channel link)

### What entry points must NOT do
- Business logic (event type determination, transcript cache management, channel archival)
- Workflow orchestration (deciding which workflow to start)
- Side effects (these belong in the service)
- Duplicate logic that exists in another entry point

### Adding a new entry point (e.g., Teams, Discord, new API endpoint)
1. Create a controller/handler that normalizes input
2. Call `IncidentLifecycleService` — same methods, same interface
3. Return platform-specific response
4. Never duplicate the service logic — if the service doesn't support what you need, extend the service

## IncidentLifecycleService

All incident write operations go through `IncidentLifecycleService` (`app/services/incident_lifecycle_service.rb`). This is the single source of truth for what happens when an incident is created, updated, closed, reopened, or has a lead assigned.

```ruby
service = IncidentLifecycleService.new(workspace)

# Create — creates incident record, starts IncidentCreationWorkflow (channel, announcements, etc.)
incident = service.create(declared_by:, incident_status:, incident_severity:, name:, source:, ...)

# Update — records change event, starts IncidentUpdateWorkflow (channel topic, announcement update)
service.update(incident, { summary: "New info" }, changed_by: member, message: "Status update")

# Close — records change, expires transcript cache, starts IncidentCloseWorkflow, schedules channel archival
service.close(incident, { incident_status: resolved_status }, changed_by: member)

# Reopen — records change, clears transcript cache, unarchives channel, starts IncidentReopenWorkflow
service.reopen(incident, { incident_status: active_status }, changed_by: member, reason: "False alarm")

# Assign lead — records change, starts LeadAssignmentWorkflow (channel topic, lead DM, announcement)
service.assign_lead(incident, lead_member, changed_by: member)
```

The service:
- Takes `changed_by` as a `WorkspaceMembership` (works for both Slack users and API key creators)
- Derives workflow context (e.g., `platform_user_id`) from the membership — no platform-specific IDs passed by callers
- Handles all side effects: transcript cache, channel archival, workflow start
- Is independently testable (`test/services/incident_lifecycle_service_test.rb`)

## Thin Controllers

Controllers validate requests, normalize payloads, dispatch synchronously, and render the response. No business logic. Slack requires response within 3 seconds (trigger_id expiration) — the controller stays in-process and meets that budget by relying on handlers to enqueue jobs when their work is heavy.

```
Api::V1::CommandsController     → Slack::CommandParser.parse     → ensure_membership! → CommandDispatcher.dispatch     → render JSON / head :ok
Api::V1::InteractionsController → Slack::InteractionParser.parse → ensure_membership! → InteractionDispatcher.dispatch → render JSON / head :ok
```

`ensure_membership!` (in `Api::V1::BaseController`) lazily provisions a `WorkspaceMembership` for the acting Slack user via `WorkspaceMemberProvisioner` so downstream handlers can trust `find_by!(platform_user_id:)`. Best-effort — provisioning failure logs and dispatch continues.

Controllers are the platform-specific boundary — they normalize payloads into platform-agnostic objects before passing to dispatchers.

### When to enqueue from a handler

Most handlers stay sync. A handler should enqueue its own job when **any** of these is true:

- The work calls an AI provider or another slow external API (`Commands::GeneratePostmortem`, `Commands::GenerateCatchup`).
- The work hits paginated Slack endpoints (`users.list`, `conversations.list`) or fans out N sequential API calls (`Commands::InviteResponders` resolve+invite path).
- The work could plausibly exceed ~1.5s on the slowest realistic workspace (leaves headroom inside Slack's 3s budget for signature verify, membership provisioning, and dispatch).

Pattern (see `Commands::InviteResponders` + `IncidentInviteJob` + `IncidentInviteService#resolve_and_notify!` as the reference):

1. Handler does cheap precondition checks; if heavy work is needed, calls `MyJob.perform_later(...)` with primitive args (ids, text, channel_id, user_id — never AR records).
2. Handler returns an immediate ephemeral acknowledgment (`Command.ephemeral(":hourglass_flowing_sand: …")`).
3. Job loads records and calls a single service method that owns the whole flow (work + final notification via `adapter.post_ephemeral`).
4. Job is a thin shell — no business logic, no Slack calls. Service owns the orchestration; adapter owns the platform calls.

Handlers that must stay sync regardless of cost: anything that opens a modal. `trigger_id` expires in 3s and cannot be used from a job.

**Inertia controllers** follow the same thin pattern. Query filtering belongs in model scopes (chainable, independently testable). Serialization belongs in serializer classes (`app/serializers/`). Aggregations and computed metrics belong in POROs (e.g., `DashboardStats`). The controller parses params, chains scopes, paginates, and renders — no inline SQL, no serialization loops, no metric calculations.

## Dispatchers

Route to handlers using lookup tables. Fall back to `UnknownHandler`.

- `CommandDispatcher` — routes on `command.command_name` + `command.subcommand`
- `InteractionDispatcher` — routes on `interaction.type` + `callback_id`/`action_id`

### Authorization

Slack is an entry point like the API and MCP, so it has one gate, in its dispatchers. Every handler declares what it authorizes as with `authorize_as` (`HandlerAuthorization`, the same idiom as `Mcp::Tools::Base`), and the dispatcher runs `handler.execute` inside `AbilityGateway.authorize!` via `AuthorizedDispatch`. A handler that touches nothing declares `authorizes_nothing`; a handler that declares neither raises, so a new one cannot arrive ungated.

- `/ff` routes through `Commands::HomeHandler`, so `CommandDispatcher.authorizing_handler` resolves the leaf the subcommand names and checks *its* declaration. `HomeHandler::SUBCOMMAND_HANDLERS` is the single routing table both the dispatch and the authorization read.
- Modal openers declare a read and the submission handler declares the write, so a refusal for a gated user lands on submit rather than on the button.
- The acting principal is the clicker's `WorkspaceMembership`, provisioned on demand by `Interaction#principal` / `Command#principal`. No principal means no dispatch: the call is refused rather than run unattributed.
- `Denied` and `PendingApproval` both come back as an ephemeral. Slack has no retry, so a parked call stores its payload on the approval (`ApprovalResumption.park!`) and is replayed by `AbilityApprovalResumptionJob` once someone approves.
- Slack participation by a human is exempt from the invocation ledger, since `record_change!` already writes the `IncidentEvent` timeline. Tool calls are still ledgered.
- **`EventDispatcher` is not gated.** Reaction-to-action, reaction-to-followup, and shoutout-from-reaction write through the same services a gated button does, so an approval policy on `incidents.update` parks the button and not the emoji. The actor on an event is always a human in a channel, so nothing an agent can reach is currently ungated, but that stops being true the moment an event handler can be triggered by anything else.

## Handlers

The "handler" layer is split by namespace, with different naming conventions reflecting different semantics:

- **`app/services/commands/`** — Slack slash-command handlers. Named as action verbs without a `Handler` suffix (e.g. `Commands::DeclareIncident`, `Commands::ChangeStatus`, `Commands::AssignLead`). The class name reads as the user's intent; the `Commands::` namespace already marks the architectural layer. The dispatch site reads like an English description (`on SUBCOMMAND_STATUS, Commands::ChangeStatus.execute(command)`). One exception: `Commands::HomeHandler` keeps the suffix because it's the sub-dispatcher, not a leaf action — it routes `Identifiers::SUBCOMMAND_*` to the corresponding command class.
- **`app/services/interactions/`** — Slack interaction handlers (button clicks, view submissions, shortcuts). Keep the `Handler` suffix (e.g. `Interactions::HomeContinueHandler`, `Interactions::UnknownHandler`). Interaction names describe *what UI event happened*, not an action — `Handler` reads naturally as "handles this event."

Both layers share the same shape:

Class methods with `self.execute(command)` or `self.execute(interaction)`. Stateless. Return response hashes or nil.

They are thin — only guards, routing, and delegation:
- Guard clauses (`return ephemeral("...") unless command.workspace`)
- Route to the right service or adapter method
- Return the response hash

Never put in a handler: DB queries beyond `command.workspace` / `command.incident`, business logic, platform-specific formatting (Block Kit, Slack mrkdwn), or response building. That belongs in services (business logic) or the adapter (platform-specific output).

`command.workspace` and `command.incident` are memoized on `Command` — call them directly, no local variable needed.

**Terminal-state guards.** `Command#incident` resolves through the `active` scope, so a slash command run in a resolved or canceled incident channel never finds one. Buttons and modals have no such filter: `QuickActions` drops Escalate and Make me Lead once the incident is over, but a Slack client can still be rendering the version that had them, and a modal can sit open while someone else closes the incident. Any handler acting on an incident asks the model, never the lifecycle stage directly — `Incident#escalation_blocked_reason` and `Incident#lead_assignment_blocked_reason` return one sentence or nil on top of `Incident#terminal?`. A view submission returns that sentence as `response_action: "errors"`; a button click posts it with `Interactions::TerminalNotice`. A stale click always gets an answer, never silence.

Handlers decide whether to dispatch sync or enqueue a job — see [When to enqueue from a handler](#when-to-enqueue-from-a-handler). The controller never decides; it always calls the handler the same way.

**Naming new commands:** verb first, noun after — `DeclareIncident`, `ChangeStatus`, `AssignLead`, `GeneratePostmortem`. Filename matches: `declare_incident.rb`, etc. If the command opens a modal as its only action, name it after the *intent* rather than the implementation (`AssignLead`, not `OpenLeadModal`). Only fall back to `Open<Thing>` when the intent really is "show this view" (`OpenHome`).

## Normalizers

Platform-specific payloads are normalized into platform-agnostic POJOs at the boundary (controllers/jobs) before reaching dispatchers and handlers.

- `Slack::CommandParser.parse(payload)` → `Command` (ActiveModel with validations) — called in `CommandsController`
- `Slack::InteractionParser.parse(payload)` → `Interaction` (plain PORO with attr_readers) — called in `InteractionsController`

Dispatchers and handlers only receive normalized objects — never raw payloads. Handlers access normalized fields (`interaction.user_id`, `command.trigger_id`).

## Slack Events (third entry path)

Alongside commands and interactions, Slack pushes **events** (channel messages, reactions, pins, app mentions, member joins). Unlike commands, events have no 3-second response budget — the controller acks immediately and all work is async:

```
Api::V1::EventsController → ProcessEventJob → EventDispatcher → Events::<Type>Handler
```

- `EventsController` handles `url_verification` inline, then enqueues `ProcessEventJob` with the raw payload and returns `head :ok`.
- `EventDispatcher` routes on `Identifiers::EVENT_*` to handlers in `app/services/events/` (`MessageHandler`, `ReactionAddedHandler`, `PinAddedHandler`, `PinRemovedHandler`, `AppMentionHandler`, `MemberJoinedChannelHandler`). Unknown types are logged and dropped.
- These handlers power transcript capture (`MessageHandler` → `IncidentTranscriptMessage`), reaction-to-action/followup/shoutout creation, pin timeline events, and AI responses to @mentions.
- Slack does **not** redeliver events after the 200 ack, so `ProcessEventJob` retries transient DB failures itself — a dropped job loses the event.

Events handlers follow the same thinness rules as command/interaction handlers.

## Services

Encapsulate business logic. Each method is independently callable (from workflows, console, or controllers). Use adapters for platform operations.

- `IncidentLifecycleService` — **shared write operations for all entry points** (create, update, close, reopen, assign lead). Both Slack handlers and API controller call this. See [IncidentLifecycleService](#incidentlifecycleservice) above.
- `IncidentCreationService` — incident creation flow details (channel, metadata, announcements). Called by `IncidentCreationWorkflow`.
- `WorkspaceSetupService` — workspace setup flow

Pattern:
```ruby
adapter = WorkspaceAdapter.for(workspace)
adapter.create_channel(name: ..., is_private: ...)
```

**Why services exist here — platform-agnostic coordination:**
Services are not a generic "service layer." They exist because Firefight bridges to external platforms (Slack now, Teams later). The business logic (record event, start workflow, set metadata) is identical regardless of platform, but the operations (create channel, post announcement) are platform-specific. Services own the shared "what happens," adapters own the platform-specific "how." Without multi-platform coordination, most services could live on models.

**When to use a service vs. model methods:**
- **Service** — orchestrates across platform boundaries or multiple systems: model writes + workflow starts, cache expiry, channel archival, job scheduling (e.g., `IncidentLifecycleService#close` updates the incident, expires transcript cache, starts a workflow, and schedules channel archival)
- **Model** — manages its own state and records its own events. If the logic is just "update my fields and record the change," it belongs on the model or a concern (e.g., `Postmortem#update_content!` wraps `record_change!` + `update!` — no service needed)

Don't create a service class that wraps a single model call. That's unnecessary indirection, not architecture.

**Litmus test before creating anything in `app/services/`:** does it call an adapter, start a workflow, or touch another system (cache, jobs, external API)? If no, it is domain logic and belongs on the model or a concern in `app/models/<model>/` — no matter how algorithm-shaped it looks. Example: policy rule evaluation is a pure function over `Policy`/`PolicyRule` data, so it lives in `Policy::Evaluation` (`app/models/policy/evaluation.rb`), not in a `PolicyRouter` service.

## Adapters

Platform abstraction layer. `WorkspaceAdapter.for(workspace)` is the factory — returns platform-specific adapter (e.g., `Slack::WorkspaceAdapter`). Always use the factory, never instantiate platform adapters directly.

Adapters have two levels of methods:
- **Low-level**: generic operations (`post_message`, `open_modal`, `pin_message`, `post_ephemeral`)
- **High-level**: intent-based operations that encapsulate UI building (`open_incident_creation_modal`, `open_home_modal`, `update_home_modal`, `post_incident_quick_actions`, `post_incident_announcement`)

Handlers and services call high-level adapter methods — never reference platform-specific builders (`Slack::Messages::*`, `Slack::Modals::*`) directly. UI building stays inside the adapter layer.

Adapters catch platform-specific errors and re-raise as `AdapterError` subclasses:
- `Slack::Client::TriggerExpiredError` → `AdapterError::TriggerExpired`
- `Slack::Client::ChannelExistsError` → `AdapterError::ChannelExists`

Services and handlers rescue `AdapterError` subclasses — never platform-specific errors.

Adapters return normalized hashes: `{ channel_id:, channel_name: }`, `{ message_ts: }`, `{ success: true }`.

**Platform boundary rule**: `Slack::Client` is only called from `Slack::WorkspaceAdapter`. No Slack-specific code outside `app/adapters/slack/`.

## Domain Events — Trackable + Recordable

Every meaningful state change to `Incident`, `IncidentAction`, or `Postmortem` is recorded as an `IncidentUpdate` / `IncidentActionUpdate` / `PostmortemUpdate` (the immutable snapshot — full state at that moment + `changed_fields` diff) plus an `IncidentEvent` (the event-bus row linking back to the snapshot via `delegated_type :eventable`).

Models opt in via two paired concerns:

- `Trackable` (`app/models/concerns/trackable.rb`) — on the live model. Provides `record_change!(event_type, by:, message: nil, metadata: nil) { ... }`. Diffs `snapshot_attributes` before/after the block, writes the snapshot + event in one transaction.
- `Recordable` (`app/models/concerns/recordable.rb`) — on the snapshot model. Declares `records SourceClass, recorder: :column_name` and wires `has_one :incident_event, as: :eventable`.

```ruby
class Incident
  include Trackable
  tracked_by IncidentUpdate

  def snapshot_attributes
    { incident: self, workspace_id:, incident_status:, ... }
  end
end

class IncidentUpdate < ApplicationRecord
  include Recordable
  records Incident, recorder: :created_by
end

incident.record_change!(IncidentEvent::INCIDENT_RESOLVED, by: member) do
  incident.update!(incident_status: resolved_status)
end
```

Pass no block for "this just got created" — the diff is empty.

Adding a new trackable model: create the snapshot table (mirroring tracked columns + `update_type`, `changed_fields`, recorder FK), include the concerns, add event_type constants to `IncidentEvent::EVENT_TYPES`, add the pair to `IncidentEvent::UPDATE_TYPE_MAP`, append the recordable class to `IncidentEvent`'s `delegated_type :eventable, types: [...]`.

**Domain event publication** runs from `IncidentEvent`'s `after_create_commit :publish_to_event_bus` → `ProcessDomainEventJob`. The commit hook lives on the model because the canonical "this event happened" moment is the event row's commit; pushing publication into the service layer means every event-creation site has to remember to publish, and we'd lose events on accidental raw `incident_events.create!`.

**Events without a recordable** (`MESSAGE_PINNED`, `INCIDENT_ESCALATED`, `ESCALATION_ACKNOWLEDGED`, `RELATIONSHIP_CREATED`, etc.) are still created directly with `incident.incident_events.create!(event_type:, user:, metadata:)`. They have no eventable; their payload lives flat in `metadata` (no `details:` nesting).

## Outbound Webhooks

Domain events fan out to customer-configured webhooks:

```
IncidentEvent commit → ProcessDomainEventJob → EventRouter → Webhooks::DispatchJob
                     → WebhookDelivery (row per attempt) → Webhooks::DeliveryService
```

- `EventRouter` maps each `IncidentEvent::*` type to subscribers (`SUBSCRIBERS` table); webhook-worthy events route to `Webhooks::EventSubscriber`, internal-only events map to `[]`. New event types must be added to this table explicitly.
- `Webhooks::DispatchJob` finds the workspace's webhooks subscribed to the event type (`triggered_by` scope) and creates a `WebhookDelivery` per webhook. The payload is **snapshotted at dispatch time** (`Webhooks::PayloadRenderer`, shared jbuilder partials in `app/views/shared/`) so retries resend identical bytes.
- `Webhooks::DeliveryService` sends it: timestamped HMAC signing (scheme `v1`), 7s endpoint timeout, 100KB response cap, and `Webhooks::SsrfProtector` blocks private/internal targets.
- `WebhookDelinquencyTracker` counts consecutive failures per webhook; sustained failure (threshold 10 over 1h) deactivates the webhook and `Webhooks::DeactivationNotifier` informs the workspace. `Webhooks::CleanupJob` prunes old deliveries.

## Entitlements (open-core seam)

Paid/cloud features are gated through `Entitlements` (`app/models/entitlements.rb`), never hardcoded flags:

```ruby
Entitlements.allows?(workspace, Entitlements::AI)   # → true/false
Entitlements.check(workspace, feature)              # → Result (allowed? + message)
```

- The default backend is `Entitlements::OpenSourceBackend`, which **always allows** — self-hosters get every core feature with zero configuration.
- The proprietary cloud build swaps in its own backend (trial state, credit caps) via `Entitlements.backend=`. That code lives in the private `firefight_cloud` gem, loaded only when the Gemfile's `FIREFIGHT_CLOUD` env flag is set at build time — it is never bundled or locked for self-hosters, and the app must always run without it.
- Rules: gate new premium-capable features through `Entitlements.allows?` with a new feature constant; never reference `firefight_cloud` from app code; never make core behavior depend on the gem's presence.

## Identifiers

All callback_ids, action_ids, and subcommand strings are centralized in the platform-agnostic `Identifiers` module (`app/models/identifiers.rb`). Never use magic strings. Reference as `Identifiers::INCIDENT_CREATION_MODAL`, `Identifiers::SUBCOMMAND_CLOSE`, etc.

## Key Files

```
app/adapters/
  adapter_error.rb                    # Platform-agnostic error hierarchy
  workspace_adapter.rb                # Factory: WorkspaceAdapter.for(workspace)
  slack/
    client.rb                         # Slack API wrapper (Net::HTTP::Persistent pool, see http_pool)
    workspace_adapter.rb              # Slack adapter (low-level methods + includes the concerns below)
    workspace_adapter/                # High-level methods, split by concern
      incident_messaging.rb           #   post/update announcements, quick actions, resolutions, reminders
      incident_modals.rb              #   open/update incident modals
      user_operations.rb              #   user lookups, DMs
      workspace_setup.rb              #   install-time channel + welcome flow
    messages/                         # Block Kit message builders (Announcement, QuickActions, Action,
                                      #   Resolution, AiResponse, Escalation, Shoutout, ... + Formatting)
    modals/                           # Block Kit modal builders (IncidentCreation, IncidentUpdate, Lead, ...)
    interaction_parser.rb             # Raw payload → Interaction POJO
    command_parser.rb                 # Raw payload → Command POJO
    signature_verifier.rb             # Slack request signature verification
    token_manager.rb                  # Token refresh/rotation

app/models/
  command.rb                          # Platform-agnostic command (ActiveModel)
  interaction.rb                      # Platform-agnostic interaction (PORO, has platform attr)
  identifiers.rb                      # Platform-agnostic callback_ids/action_ids
  incident.rb                         # AR model with concerns (Sequencing, ChannelNaming, etc.)

app/serializers/                      # (representative — one serializer per Inertia prop shape)
  base_serializer.rb                  # Oj::Serializer base with camelCase keys + TS generation
  incident_detail_serializer.rb       # Incident → incident detail page props
  incident_list_item_serializer.rb    # Incident → dashboard list props (auto-generates TS)
  timeline_event_serializer.rb        # IncidentEvent → timeline entries

app/services/
  incident_lifecycle_service.rb       # Shared write operations (create, update, close, reopen, lead)
  incident_invite_service.rb          # Resolve targets + invite + notify (used by InviteHandler + IncidentInviteJob)
  command_dispatcher.rb               # Routes commands → handlers
  interaction_dispatcher.rb           # Routes interactions → handlers
  incident_creation_service.rb        # Incident creation details (channel, metadata, announcements)
  workspace_setup_service.rb          # Workspace setup business logic
  workspace_member_provisioner.rb     # Lazy provisions WorkspaceMembership from a Slack user_id

app/jobs/
  incident_invite_job.rb              # Async resolve+invite for InviteHandler (paginated users.list path)

app/views/shared/
  _incident.json.jbuilder             # Shared incident serialization (used by API + webhooks)
  _actor.json.jbuilder                # Shared actor serialization (used by API + webhooks)

app/workflows/                        # All inherit SolidWorkflow::Base (engine: engines/solid_workflow/)
  incident_creation_workflow.rb       # Thin delegates to IncidentCreationService
  incident_close_workflow.rb          # + update/reopen/escalation/link/lead/summary workflows
  slack_workspace_setup_workflow.rb   # Thin delegates to WorkspaceSetupService
```
