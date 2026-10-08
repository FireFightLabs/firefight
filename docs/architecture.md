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
2. **Call shared service** — `IncidentLifecycleService.new(workspace).create(...)` / `.change_status(...)` / `.assign_role(...)` etc.
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

All incident write operations go through `IncidentLifecycleService` (`app/services/incident_lifecycle_service.rb`). This is the single source of truth for what happens when an incident is created, updated, closed, canceled, reopened, accepted, or has a lead assigned.

```ruby
service = IncidentLifecycleService.new(workspace)

# Create — creates incident record, starts IncidentCreationWorkflow (channel, announcements, etc.)
incident = service.create(declared_by:, incident_status:, incident_severity:, name:, source:, ...)

# Every status change. The verb is decided once, from the stage the incident
# is in and the stage the new status belongs to:
#   same stage            → update  (IncidentUpdateWorkflow)
#   live → closed         → close   (IncidentCloseWorkflow, resolved_at, archival)
#   live → canceled       → cancel  (IncidentCancelWorkflow, archival, no runbooks)
#   terminal → live       → reopen  (IncidentReopenWorkflow, unarchive)
#   triage → active       → accept
#   closed ↔ canceled     → refused with Incident#status_change_blocked_reason
# attrs may carry any incident column plus :lead. No status means a plain update.
service.change_status(incident, { incident_status: resolved_status, summary: "New info" }, changed_by: member, message: "Status update")

# Cancel with the workspace's default canceled status (the Cancel button, /ff cancel)
service.cancel_with_default_status(incident, changed_by: member)

# Assign lead — records change, starts LeadAssignmentWorkflow (channel topic, lead DM, announcement)
service.assign_lead(incident, lead_member, changed_by: member)
```

The verbs themselves (`update`, `close`, `cancel`, `reopen`, `accept`) are private. Every entry point, Slack handler or API, calls `change_status`, so none of them can pick the wrong verb for the status it was handed. Each lifecycle event owns its own workflow and step list, so a step that belongs to one event (runbook attachment on update, archival on close and cancel) is declared there rather than skipped elsewhere.

The service:
- Takes `changed_by` as a `WorkspaceMembership` (works for both Slack users and API key creators)
- Derives workflow context (e.g., `platform_user_id`) from the membership — no platform-specific IDs passed by callers
- Handles all side effects: transcript cache, channel archival, workflow start
- Is independently testable (`test/services/incident_lifecycle_service_test.rb`)

## Thin Controllers

Controllers validate requests, normalize payloads, dispatch synchronously, and render the response. No business logic. Slack requires response within 3 seconds (trigger_id expiration) — the controller stays in-process and meets that budget by relying on handlers to enqueue jobs when their work is heavy.

```
Api::V1::CommandsController     → Slack::CommandParser.parse     → CommandDispatcher.dispatch     → render JSON / head :ok
Api::V1::InteractionsController → Slack::InteractionParser.parse → InteractionDispatcher.dispatch → render JSON / head :ok
```

Who is acting is resolved once: `Command#principal` / `Interaction#principal` provision a `WorkspaceMembership` for the Slack user on the way through `AuthorizedDispatch`, before any gated handler runs, so handlers can trust `find_by!(platform_user_id:)`. A user whose profile cannot be read is refused with `AuthorizedDispatch::UNRESOLVED_MESSAGE`. An interaction from a `team_id` Firefight does not know is dropped with `head :ok` (there is no way to answer a click on an old message) and logged as `interaction.unknown_workspace`.

A modal's `private_metadata` is parsed once by `Slack::InteractionParser` into the typed `Interaction#metadata` (`ModalState::Result`). Handlers read `interaction.metadata.incident_id` and friends and never parse the string themselves. Every modal builder encodes with `ModalState.encode`, which is platform-neutral: the string is Firefight's own JSON, the platform only carries it.

Two cleanup coordinates ride in that state so a modal can tidy up after itself. `temp_message_ts` plus `channel_id` name the "writing..." placeholder a slow modal posts, deleted on submit or close through `Interactions::ModalCleanup.delete_temp_message`. `prompt_handle` is the platform's one-off reply token for the button that opened the modal (Slack's `response_url`, parsed onto `Interaction#prompt_handle`). The reaction-to-action prompt is ephemeral, so `chat.delete` cannot reach it, and the only way down is `delete_original` posted to that URL. The from-reaction handler encodes the handle, and `CreateActionItemHandler` calls `ModalCleanup.dismiss_prompt` once the item exists, never on click, so cancelling the form leaves the prompt to retry. `PlatformAdapter#dismiss_prompt(prompt_handle:)` is the contract, `Slack::Client.delete_original_response` the only place that knows the URL's shape and refuses any host but `hooks.slack.com`.

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
- Incident participation by a human (`AbilityGateway::HUMAN_SOURCES`, Slack and the dashboard, on a `WorkspaceMembership::PARTICIPATION` resource) is exempt from the invocation ledger, since `record_change!` already writes the `IncidentEvent` timeline. Everything else a human does is ledgered with its `source`, which is what makes Gateway → Activity the audit log of configuration changes. Tool calls are always ledgered. The gateway enqueues approver notification when it parks a call, and `Ability::Approval#resolve!` enqueues the parked-request replay. No model callback does either, so writing an approval row elsewhere triggers no platform traffic.
The dashboard has the same single gate, `WebAuthorization`, included by `InertiaController`. A controller declares what each action authorizes as (`authorizes Ability::Action::RESOURCE_WEBHOOKS, create: :create, update: %i[update test], delete: :destroy`) and the before_action runs the gateway with `source: web`. There is no `require_admin!`: admin-only areas are admin-only because their resource is in `Ability::Action::ADMIN_ONLY_RESOURCES`, which nothing can be granted and which `implicitly_permits?` refuses to members even for reads. The one dynamic case, a personal API token versus a service key, calls `authorize_web!` inside the action. `Denied` redirects back with an alert. `PendingApproval` parks the raw request (`ApprovalResumption.park_web!`, path, method, body and content type) and `WebRequestReplay` re-runs it through the router as the requester once approved, with the approval in the Rack env, then the requester is told by direct message. `InertiaController` shares `currentUserCan`, one flag per resource, and pages render controls from it (`useCan`), never from "is admin".

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

**Terminal-state guards.** An incident that is over must not be handed work that only a live incident can take. The rule lives on the model, twice over:

- **The model refuses.** `Incident#assign_role!` and `#unassign_role!` raise `Incident::NotActive` when `role_assignment_blocked_reason(role)` returns a sentence, and `lead=` inherits it by routing through `assign_role!`. Both directions refuse because both announce: filling the lead DMs the person and rewrites the channel topic, and every other role change posts to the channel, which `ChannelArchivalJob` may already have archived. Reporting alone is advisory — a caller that forgets to ask is exactly how this reached the API and MCP twice over. Refusing catches Slack, the API, MCP, alert ingest, the console, and whatever is written next, from one place. `IncidentLifecycleService#close` sets the lead *before* the status for this reason: the same save closes the incident, and the guard fires once the status has landed.
- **The service refuses what every surface routes through.** `IncidentActionService#create_action` calls `Incident#refuse_action_item!(action_type)`, which raises on `action_item_blocked_reason`: an action needs a live incident, a follow-up never does. Claiming a runbook step creates the action behind it, so it is refused by the same line. The dashboard ships `action_blocked_reason` and `followup_blocked_reason` on the incident and renders the plus and Claim controls disabled with that sentence, never a lifecycle-stage check of its own.
- **The service refuses what has no model write.** `IncidentLifecycleService#escalate` raises the same error on `escalation_blocked_reason`. Escalation writes an event, pages someone through a workflow, and schedules a chase, none of which is a state change on `Incident` a model guard could sit on, so the floor is the service method every entry point has to go through.
- **Every surface translates it once**, in the same rescue that already handles `AbilityGateway::Denied`: `CommandDispatcher` → ephemeral, `InteractionDispatcher` → `refuse` (which resolves a channel for a button click and for a modal submission alike), `Api::V1::ApiController` → 422 `incident_not_active`, `Mcp::ToolDispatcher` → tool error. Add a surface, add one rescue.

`role_assignment_blocked_reason` names the role rather than the verb (`its Communications Lead can no longer be changed`) because workspaces rename roles and because the same sentence has to cover clearing one. The lead keeps its own wording, which is what the Slack buttons and modals already show.

Handlers still pre-check, and that is not redundant. `Command#incident` resolves through the `active` scope, so a slash command in a channel whose incident is over never finds one. Buttons and modals have no such filter: `QuickActions` drops Escalate and Make me Lead once the incident is over, but a Slack client can still be rendering the version that had them, and a modal can sit open while someone else closes the incident. A view submission needs `response_action: "errors"` against a specific `block_id`, which only the handler knows, so it asks `escalation_blocked_reason` / `lead_assignment_blocked_reason` and hangs the sentence on the right field; a button click posts it with `Interactions::TerminalNotice`. Guard at the boundary for the message, refuse at the model for the safety.

`EscalateIncidentHandler` is thin for the same reason every other handler is: it resolves the incident and the member, pre-checks for the modal error, and hands the work to `IncidentLifecycleService#escalate`. The event, the workflow, and the reminder job all live in the service, which is how `escalate_incident` over MCP and `POST /api/v1/incidents/:id/escalate` inherit the guard rather than having to remember it.

**`escalated_to` is a person, not an id.** It takes a `WorkspaceMembership` or the platform id of someone the platform knows, and normalizes both into `Incident::EscalationTarget`. Both are legitimate: escalating to someone is not what makes them a billable member, so a Slack mention of a non-member still resolves to a name and an avatar. The target answers the same questions any actor does (`platform_user_id`, `actor_display_name`), so a message names it without asking which kind it is.

**The escalation event is the only thing the workflow and the chase carry.** `IncidentEscalationWorkflow`'s context is `{ escalation_event_id }` and `EscalationAcknowledgementReminderJob` takes `(incident_id, escalation_event_id)`. Who asked (`event.actor`, polymorphic, so an agent works), who was asked and why are all on the event already, and a copy in a workflow context is a copy that can drift.

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
- These handlers power transcript capture (`MessageHandler` → `IncidentTranscriptMessage`), reaction-to-action/followup/shoutout creation, pin timeline events, and @mentions, which go to Halon's conversation in the mention's thread.
- A pin event stores the pinned message's text (`fetch_message` through the adapter) alongside its permalink, so the timeline can quote it. The fetch is decoration: an `AdapterError` leaves `message_text` nil and the pin is still recorded.
- Pins Firefight makes itself (the quick actions header at channel setup, the postmortem message when generated) are not recorded. `Incident#own_pinned_message?` names those message ids, and `PinAddedHandler` drops the event for them, for both pin and unpin. The timeline lists only pins a person chose to make.
- Slack does **not** redeliver events after the 200 ack, so `ProcessEventJob` retries transient DB failures itself — a dropped job loses the event.

Events handlers follow the same thinness rules as command/interaction handlers.

## Services

Encapsulate business logic. Each method is independently callable (from workflows, console, or controllers). Use adapters for platform operations.

- `IncidentLifecycleService` — **shared write operations for all entry points** (create, update, close, reopen, assign lead). Both Slack handlers and API controller call this. See [IncidentLifecycleService](#incidentlifecycleservice) above.
- `IncidentCreationService` — incident creation flow details (channel, metadata, announcements). Called by `IncidentCreationWorkflow`.
- `IncidentUpdateService` — every message an incident's lifecycle posts. Its four announcement-thread replies (update, resolution, reopen, escalation) also reach each subscriber (`Incident::Subscriptions`) as a DM carrying the same blocks. The service passes `subscriber_user_ids`, the adapter delivers, and a DM that fails is logged and skipped so one bad recipient never silences the thread.
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

A workspace with no platform yet (`platform` nil, `Workspace#chat_connected?` false) gets `UnconnectedAdapter`, which raises `AdapterError::NotConnected` from every method, the contract's and any a platform adapter adds beyond it. Callers already rescue `AdapterError`, so a job or a setting that reaches for the platform fails the way it would on an outage. A page that would otherwise ask the platform for something (the channel picker, the member directory, the onboarding channel link) checks first or rescues `NotConnected` and shows what Firefight has. Incidents run in channels, so `IncidentLifecycleService#create` refuses with `Incident::CreationBlocked` and `Workspace#incidents_blocked_reason` ("Connect Slack first to run incidents."), which the dashboard flashes, the API answers as `incidents_blocked` (422), MCP and Halon's chat return as the tool's error, and `CurrentWorkspaceSerializer` ships so every Declare button is disabled with it as its tooltip.

`PlatformAdapter` is the whole contract, and nothing outside `app/adapters/slack/` names a `Slack::` constant (ArchSpec enforces it, with no grandfathered exceptions left). The seams that keep it that way:

- **Modals are built by kind.** `adapter.build_modal(PlatformAdapter::Modal::LEAD, incident)` returns the opaque view that `open_modal`, `push_modal`, `update_modal` and `form_update_response` accept. `Slack::WorkspaceAdapter::MODAL_BUILDERS` maps each kind to its builder, and anything only Slack needs (the `team_id` in a channel deep link) is filled in there. `metadata:` carries an encoded `ModalState`.
- **Form submissions are parsed by the adapter.** `adapter.parse_form_submission(form_slug:, values:, incident:)` returns `system_attrs`, `custom_fields`, `errors` and `first_error_field_key`. A handler answers with `adapter.form_error_response(field_key, message)` or `adapter.form_update_response(view)`, never with a `response_action` hash of its own. The mapping from a field key to a block id lives in `Slack::Modals::FieldBlocks` only.
- **People in free text are the platform's to resolve.** `adapter.people_targets?(text)` and `adapter.resolve_people(text)` wrap `Slack::HandleResolver`.
- **Which kind a callback names is an `Identifiers` table** (`ACTION_ITEMS_LIST_KINDS`, `ACTION_ITEMS_FORM_KINDS`), and the kind's action type is `IncidentAction::ACTION_TYPE_BY_KIND`.
- **Credentials refresh through the factory.** `RefreshPlatformCredentialsJob` calls `WorkspaceAdapter.refresh_expiring_credentials(buffer:)`, which asks each platform adapter class in turn.
- **Transcript messages carry `message_id`, `thread_id` and `platform_user_id`**, the platform's identifiers under Firefight's names.

Adapters have two levels of methods:
- **Low-level**: generic operations (`post_message`, `open_modal`, `pin_message`, `post_ephemeral`)
- **High-level**: intent-based operations that encapsulate UI building (`open_incident_creation_modal`, `open_home_modal`, `update_home_modal`, `post_incident_quick_actions`, `post_incident_announcement`)

Handlers and services call high-level adapter methods — never reference platform-specific builders (`Slack::Messages::*`, `Slack::Modals::*`) directly. UI building stays inside the adapter layer.

Platform clients raise `AdapterError` subclasses directly, so there is one error family in the whole app. `Slack::Client::SLACK_ERROR_CODES` maps each Slack error code to its `AdapterError` (`expired_trigger_id` → `TriggerExpired`, `name_taken` → `ChannelExists`, `token_revoked` → `AuthRevoked`, …), 429s become `RateLimited`, 5xx become `ServerError`, and a transport failure that outlives the retries becomes `AdapterError::Unavailable`. Nothing platform-specific, not even a `Net::ReadTimeout`, leaves `app/adapters/`. `Slack::WorkspaceAdapter#translate_errors` only adds the side effect a revoked install needs.

A revoked install (`token_revoked`, `account_inactive`, or a refresh token Slack no longer accepts) marks the workspace disconnected (`Workspace::Connection`). The dashboard keeps working and shows a banner asking an admin to reconnect through `/onboarding/reinstall`, which skips the invite gate for a workspace that already exists. The hourly token refresh skips disconnected workspaces. A reinstall clears the flag.

**First run.** The invite gate is off unless `INVITE_REQUIRED` is set, read once into `config.x.invite_required` and asked through `InviteCode.required?` by the install service, the sign-in callback, the onboarding controller and the claim endpoint. A first install creates the workspace's `WorkspaceOnboarding` row with the installer and the setup workflow posts the welcome checklist and keeps its message id on that row. The coach in the first test incident's channel is `OnboardingWalkthroughService#advance!`, called from the creation workflow, the close workflow, the postmortem service and the onboarding progress job, and it posts only the step the incident has just earned. The quick actions carry a Resolve button (`Interactions::ResolveIncidentButtonHandler`) that opens the same close modal as `/ff resolve`, so the whole loop is clicks. Progress is never stored: `WorkspaceOnboarding#stage` reads it off the workspace's first test incident, and the dashboard dialog is the installer's until they dismiss it. The onboarding declares a test incident (`Incident#is_test`, set from the welcome button's `ModalState` and the dialog's `test` param) so the first run never touches the numbers: `Incident.real` keeps test incidents out of `DashboardStats`, `Webhooks::DispatchJob` never fires for one, and every other surface treats it like a real incident with a label.

**Sign-in.** Every way to sign in ends in `AuthenticationService#sign_in_with(claims)`, so which person a sign-in reaches is decided once. A `UserIdentity` (`google`, `slack` or `email`, `uid` unique per provider) is looked up first, then a `User` holding an email the provider verified. An unverified email never links and never creates a person, and an email change at the provider never moves an account, since the identity is matched before any email. A person's first identity sends nothing, and each one after it sends `SignInMailer#new_method` when mail is set up. `User#email` is stored lowercased and trimmed, unique on `lower(email)`.

- **Slack** (`slack_openid`) keeps its flow: `SlackAuthenticationService` builds the claims with uid `team_id/user_id`, creates the person when nobody holds a verified email, and refuses with `AuthOutcome.refused` when Slack has not verified it. Existing members were given their Slack identity by migration, so they are matched by id.
- **Google** (`google_oauth2`, `openid email profile`, `prompt=select_account`) is registered only when `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` are set (`config.x.google_sign_in`). It refuses an email Google has not verified, even from a linked account.
- **Email** sends a `LoginToken`: only its SHA-256 digest is stored, it lives 15 minutes and serves one purpose (`sign_in`). `POST /auth/email` answers "check your email" for every valid address and sends the link whether or not anyone holds it, so the page never reveals an account. The link opens `GET /auth/email/confirm`, which only shows a button, because mail scanners fetch links. The button's POST consumes the token in one guarded `update_all` (`LoginToken.consume`) and closes every other open link for the address. The token rides in the query and body, never the path, so request logs filter it.
- A Google or email sign-in that reaches nobody with a workspace goes on to `/signup/workspace` (`WorkspaceSignupsController`). So does a Slack sign-in from a team Firefight does not know while self-serve signup is on, carrying the team's name as the suggested workspace name and the team id as the one it later connects. Off, a Slack sign-in keeps the install flow below. `SignInSession#start_signup` resets the session and holds the person as `signup_user_id`, or, for someone Firefight has never seen, as the verified claims (`signup_claims`), so nobody is created until they create a workspace. An email link carries no name, so the page asks for one. `SignInSession#start_session` resets the session and keeps `return_to` for every method.
- Both wait behind the global flag `FeatureFlags::SELF_SERVE_SIGNUP` and, for email, on mail being set up (`config.x.mail_configured`, from `SMTP_ADDRESS`, `MAIL_FROM` and `APP_HOST` in deployed environments, always on in development with letter_opener). `SignInMethods` answers which methods the sign-in page offers, and the callbacks refuse a method it does not.
- Profile (`/app/profile`) lists a person's identities and removes one through `UserIdentity#remove!`, which locks the person and refuses the last (`removal_blocked_reason`).
- Rack::Attack caps `POST /auth/email` at 5 a minute per IP and 5 an hour per address (`RackAttackParams.email` reads JSON or form bodies), and `POST /auth/email/confirm` at 20 a minute per IP.

**Setup checklist.** After the founder's letter an admin works through `/app/setup` (`SetupController`, page `setup/index`), seven steps in order: the account (done by signing in), Halon's AI, the stack, who can do what, Meet Halon, Slack and the test incident. The rules live in `WorkspaceOnboarding::Checklist`. An answer a person gives is a column on the onboarding row (`ai_choice`, `stack_answers` by category slug, `permissions_reviewed_at`, `halon_answered_at`, `slack_skipped_at`), so the checklist resumes on any device. Slack and the test incident are read from the workspace and its first test incident. `steps` marks each `done`, `skipped`, `current` or `waiting`, and the first one not finished is current. Meet Halon is required, so while Halon cannot answer (`Investigation.unavailable_reason`) it stays current with that reason as its note, pointing back to the AI step only for a model Halon does not know (`Investigation::MODEL_NOT_SET_UP`). Which categories the first question names is the registry's `in_first_question`, and the chat's setup guide is `halon_guide`. The last answer, or any page visit that finds every step finished, stamps `checklist_completed_at` with a guarded `update_all` (`finish_if_done!`).

- **Cannot be dismissed.** `ContinuesSetup`, included in `InertiaController`, sends an HTML GET from anyone `steers?` (setup not finished, and the gateway lets them update the workspace) to the checklist, keeping the flash the page was going to show. Forms, JSON reads and the controllers that are part of setup skip it: the checklist, the onboarding and sign-in controllers, the chat, and the OAuth legs of connecting a tool or an AI account. A member never sees setup. A Slack-connected workspace that predates the checklist is marked done by `FinishChecklistForConnectedWorkspaces`.
- **Halon's AI.** The workspace's own key through the AI accounts card (`AiAccountProps`, shared with Settings, Workspace), done once an account passes its check. Firefight credits are offered where `Entitlements.ai_credit` answers, and the deployment's own keys where `AiFunding.house_payer` is the operator's or Firefight's. `ai_choice_blocked_reason` says why a choice cannot be taken yet and the page shows it.
- **The stack.** Every category in `config/integration_providers.yml`, one at a time, each with a `halon` sentence and `required` for code, hosting and observability. A category is answered with `connected`, which needs a connection whose check passed, or `unused` ("We don't use this"), refused for a required one (`WorkspaceOnboarding.category_answer_blocked_reason`, shipped per category by `OnboardingCategorySerializer`). The connect dialogs are the gallery's, with `return_to` set to the checklist, which `IntegrationsController#safe_return_to` accepts. `answer_category!` merges into the jsonb in one statement.
- **Meet Halon.** The real chat, with `setupGuide` (`AgentChatsController::PROP_SETUP_GUIDE`) drawn above it and its first question (`first_question`, naming the hosts and databases connected) in the composer. `Conversation::Runner` calls `halon_answered!` before telling the page an answer finished, and only an admin's own chat counts.
- **Slack and the test incident.** Connecting goes through `POST /onboarding/connect-slack`, back to the dashboard and so to the checklist. "Not now" stamps `slack_skipped_at`, which also skips the test incident, and finishes setup. With Slack connected the test incident is the same declare dialog with `test`, and declaring it finishes setup on the way to the incident.

**Workspaces without Slack.** `WorkspaceSignupService#create` makes the person from the held claims if needed and calls `Workspace.sign_up!` (`Workspace::Signup`) in one transaction: the invite code is redeemed there when `InviteCode.required?`, for every sign-in method, then the same defaults an install gives (`setup_incident_configuration!`, `setup_catalogue!`, `grant_agent_defaults!`), the owner membership with no `platform_user_id`, the `WorkspaceOnboarding` row and `created_by`. The person is signed in and sent to `Entitlements.next_step_path(workspace)` or the founder's letter. Rack::Attack caps `POST /signup/workspace` at 5 an hour per IP.

- **Connecting Slack later.** `POST /onboarding/connect-slack` is a workspace update, so only admins pass the gateway. It sets `session[:connecting_workspace_id]` and goes through the same install page and OmniAuth `slack` callback. `SlackAuthenticationService#handle_install(connecting:)` refuses a team that belongs to another Firefight workspace (never merged, the unique index catches a race), still refuses a team other than the one the person signed in with (`pending_team_id`), and otherwise `Workspace.process_slack_installation(workspace:)` fills the platform columns through `Workspace#connect_slack!`, keeping the chosen name. The installer's membership gains its `platform_user_id`. The first connect starts `SlackWorkspaceSetupWorkflow`, as a first install does, and announces the connect (see Telling the team). A member who joined before Slack gets their platform id the first time they show up there: `WorkspaceMemberProvisioner` and the Slack sign-in match an existing membership by person before creating one, and `WorkspaceMembership#link_platform_user!` never replaces an id already set. A person holds one membership per workspace (unique `workspace_id, user_id`).
- **Email invitations.** Admins invite from Members (`WorkspaceInvitationsController`, a workspace update in the gateway). `WorkspaceInvitation` is the pending row (one open per address per workspace), and its link is a `LoginToken` with purpose `workspace_invite`, a week long, tied to the invitation so using or resending it closes only that invitation's other links. `WorkspaceInvitationService` sends `WorkspaceInvitationMailer#invite`. The link opens `GET /auth/invitation`, which only shows a button, and the POST consumes the token, signs the person in through `AuthenticationService` (creating them with an email identity if new) and seats them as a member through `WorkspaceInvitation#accept!`, a guarded update that a revoke cannot race. Resend and revoke are on each pending row. Invitations wait on self-serve signup and outgoing mail (`WorkspaceInvitation.unavailable_reason`), since the invitee signs in again by email. Each workspace sends at most `SENDS_PER_HOUR` invitation emails an hour, resends included, and Rack::Attack caps the invitation posts at 30 an hour per IP and the accept at 20 a minute.
- **Telling the team.** `TeamWebhook` posts Firefight's own notes to the people running it, at `INSTALL_NOTIFICATION_WEBHOOK_URL`, a plain JSON POST and never a platform call. `SignupNotificationService.announce` enqueues `SignupNotificationJob` after the surrounding transaction commits, and only when the URL is set, so an unset URL enqueues and logs nothing and a failed enqueue is logged, never raised into the sign-up. It announces `WORKSPACE_CREATED` from `WorkspaceSignupService#create` and from `handle_install` when the install made the workspace (`process_slack_installation`'s `created`), naming the sign-in method kept in `session[:signup_method]` by `SignInSession#start_signup`, and `CHAT_CONNECTED` from a connect, named by `PlatformAdapter#team_label`. A connect that follows a Slack sign-up in the same team (`pending_team_id` set) is not announced, since the workspace was already announced as created with Slack. Finishing setup for a workspace that already existed announces nothing. The job retries once, then logs and drops. A hosted build can post its own notes through `TeamWebhook` the same way.
- Every page shows a banner while `chat_connected?` is false, with Connect Slack for whoever can update the workspace. The first-run dialog waits for Slack, since its test incident runs there.

Services and handlers rescue `AdapterError` subclasses — never platform-specific errors.

Adapters return normalized hashes: `{ channel_id:, channel_name: }`, `{ message_id:, channel_id: }` for anything that posts a message, `{ success: true }` for everything else.

**Platform boundary rule**: `Slack::Client` is only called from `Slack::WorkspaceAdapter`. No Slack-specific code outside `app/adapters/slack/`.

## Domain Events — Trackable + Recordable

Every meaningful state change to `Incident`, `IncidentAction`, or `Postmortem` is recorded as an `IncidentUpdate` / `IncidentActionUpdate` / `PostmortemUpdate` (the immutable snapshot — full state at that moment + `changed_fields` diff) plus an `IncidentEvent` (the event-bus row linking back to the snapshot via `delegated_type :eventable`).

Models opt in via two paired concerns:

- **Event metadata names things, never just ids.** An `IncidentEvent` that points at something stores the id and the name the timeline will say (`runbook_id` + `runbook_name`, `related_incident_id` + `related_identifier`, `escalated_to_member_id` + `escalated_to_name` + `escalated_to_avatar_url`). `IncidentEvent#subject_label` reads those names, and `IncidentEvent::References` resolves the ids once per timeline for links and avatars. Automatic runbook attachment stores `reason` (`Runbook#attach_reason`, built from `IncidentCondition#to_sentence`), escalation stores `reason`, and both surface as the entry's details.
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

**Events without a recordable** (`MESSAGE_PINNED`, `INCIDENT_ESCALATED`, `ESCALATION_ACKNOWLEDGED`, `RELATIONSHIP_CREATED`, `MILESTONE_NOTED`, etc.) are still created directly with `incident.incident_events.create!(event_type:, user:, metadata:)`. They have no eventable; their payload lives flat in `metadata` (no `details:` nesting).

### `MILESTONE_NOTED` metadata contract

`milestone.noted` is what an AI pass read out of the channel transcript once the incident ended (see [ai.md](ai.md)). It is metadata-only like a pin, and its metadata is the whole contract every surface renders from:

| Key | Is |
|---|---|
| `kind` | One of `IncidentEvent::MILESTONE_KINDS`: `hypothesis`, `finding`, `root_cause`, `mitigation`, `decision`, `blocker`, `impact`, `recovery` |
| `statement` | The one-sentence note, already naming the person it belongs to |
| `member_id`, `member_name`, `member_avatar_url` | Who said it, stored at write time so a surface never resolves an id to render the row |
| `message_id`, `message_text`, `permalink`, `said_at` | The single source message: its id, the scrubbed quote, its Slack link, and when it was said |
| `confidence` | What the model reported, kept for tuning `MIN_CONFIDENCE` against real dismissal rates |
| `inference_id` | The ledger row for the pass, so a note traces to its cost in Gateway → Activity |
| `dismissed_at`, `dismissed_by_member_id`, `dismissed_by_name` | Set by `IncidentEvent#dismiss!`, absent until someone corrects the note |

Two rules that are easy to get wrong:

- **`actor` is nil.** Firefight noted it, so the sentence reads "Firefight noted". The person in `member_*` is who *said* the thing, not who performed an action, and `IncidentEvent::References` resolves them for the avatar.
- **`created_at` is the source message's time, not the pass's.** That is what puts the note where the conversation was rather than at the end of the incident, and it means every surface orders it correctly through `chronological` without a special case.

`IncidentEvent.undismissed` is the scope every text surface reads through. Dismissal keeps the row and hides it. Only the dashboard shows dismissed notes, collected at the end of their day.

## The dashboard writes through the same services

The dashboard used to read incidents and write only their postmortems, actions
and runbook attachments. Everything that changes the incident itself lived in
Slack. `IncidentLifecycleController` closes that: resolve, cancel, reopen,
update, assign a role, link, and mark a duplicate.

It carries no rules of its own. The workspace's configured form decides what is
asked (`IncidentFormResolver`), one model decides what the answers mean
(`IncidentFormSubmission`), and `IncidentLifecycleService` decides what a status
change is. Read [forms.md](forms.md) before touching any of it.

Two things about it are worth knowing before adding a control:

- **A single-field write is only correct where Slack has one.** `/ff severity`
  and `/ff status` both open the whole Update modal, so the dashboard's severity
  and status badges open the Update dialog rather than patching one attribute.
  Doing otherwise would skip whatever else that workspace made required. The
  lead and the other roles do have their own dedicated Slack modals, so they get
  a dropdown that writes on its own through `assign_role`.
- **The platform builds its own URLs.** `PlatformAdapter#channel_url` returns
  the deep link that opens an incident's channel, and the page is handed the
  finished string. The frontend used to assemble
  `https://slack.com/app_redirect?channel=...` itself, which both leaked Slack
  into React and dropped the `team`, so a browser signed into more than one
  workspace opened the wrong one.

## Outbound Webhooks

Domain events fan out to customer-configured webhooks:

```
IncidentEvent commit → ProcessDomainEventJob → EventRouter → Webhooks::DispatchJob
                     → WebhookDelivery (row per attempt) → Webhooks::DeliveryService
```

- `EventRouter` hands every subscribable `IncidentEvent::*` type to each subscriber in turn: `Webhooks::EventSubscriber` fans it out to customer webhooks, and `Onboarding::EventSubscriber` redraws the welcome checklist in `#incidents` when the event moved the workspace's first incident (`WorkspaceOnboarding::PROGRESS_EVENTS`). Internal-only events are named in `INTERNAL_ONLY`. New event types must be added to one of the two lists explicitly.
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
- The proprietary cloud build swaps in its own backend (trial state, credit caps) via `Entitlements.backend=`. A backend may also answer `ai_account(workspace)`, whose account pays for the AI: the open-source backend says `operator`, and a backend that does not answer is taken as Firefight's own.
- Who pays for a workspace's AI after its own accounts (docs/ai.md, Who pays) is asked the same way, each with a default that keeps an install someone runs themselves free of it: `firefight_pays_for_ai?(workspace)` (Firefight's own workspaces stay on Firefight's key, true when a hosted backend does not answer), `ai_credit(workspace)` (the workspace's Firefight credits, nil when not answered), `charge_ai!(inference)` (bills a credits call, answering what it billed) and `private_ai_endpoints?(workspace)` (whether an AI account may point at a private address, true for the open-source backend and false for any other that does not answer). That code lives in the private `firefight_cloud` gem, loaded only when the Gemfile's `FIREFIGHT_CLOUD` env flag is set at build time — it is never bundled or locked for self-hosters, and the app must always run without it.
- Rules: gate new premium-capable features through `Entitlements.allows?` with a new feature constant; never reference `firefight_cloud` from app code; never make core behavior depend on the gem's presence.
- **Access.** `Entitlements::ACCESS` asks whether a workspace may be used at all. `Workspace#access_blocked` combines it with a suspension (which wins, with its own message) and returns nil or an `Entitlements::Result`, whose optional `path` names the page that lifts the block. Every checkpoint that used to ask `suspended?` asks this: the dashboard (`InertiaController#block_inaccessible_workspace`, which renders `errors/suspended` or redirects to the path, so that page's controller skips the guard), the API and MCP (403 `workspace_suspended`), alert ingest, Slack commands, interactions and events. The open-source backend always allows.
- **Daily upkeep and notices.** `Entitlements.sweep!` asks the backend's `sweep!`, for state that moves with time such as retention warnings, and is a no-op on the open-source backend. `EntitlementsSweepJob` calls it daily (`config/recurring.yml`). A backend may share a `cloudBanner` prop (`title`, `detail`, optional `action` with `label` and `href`), which `AuthenticatedLayout` draws on every page beside the Slack banners. The open-source build never sets it.
- **Next step after signup.** `Entitlements.next_step_path(workspace)` is where a new workspace goes once created, such as a plan picker. A backend that does not answer, and the open-source one, send it to the founder's letter, and the setup checklist follows it.

## Feature flags (unreleased work)

Work that is not ready for everyone hides behind `FeatureFlags` (`app/models/feature_flags.rb`), backed by Flipper with its ActiveRecord adapter:

```ruby
FeatureFlags.enabled?(workspace, FeatureFlags::CHATGPT_SIGN_IN)   # → true/false
```

- Every flag is off for every workspace until an operator turns it on. Unlike `Entitlements`, this holds on self-hosted installs too, so unfinished work never reaches anyone by default.
- Operators switch flags with rake, never from the dashboard: `bin/rails 'feature_flags:enable[chatgpt_sign_in,WORKSPACE_ID]'`, `feature_flags:disable[...]`, and `feature_flags:list`.
- A flag is a constant on `FeatureFlags` listed in `FeatureFlags::ALL`. Any other name raises `FeatureFlags::UnknownFlag`.
- A flag is either per workspace (`FeatureFlags::WORKSPACE`) or global (`FeatureFlags::GLOBAL`, asked with `enabled_globally?` and switched with `feature_flags:enable_globally[FLAG]` and `feature_flags:disable_globally[FLAG]`). A global flag is for something no workspace owns yet, such as `SELF_SERVE_SIGNUP` on the sign-in page. Using one kind as the other raises `UnknownFlag`.
- Only `FeatureFlags` may name `Flipper` (ArchSpec). State lives in the `flipper_features` and `flipper_gates` tables. Flipper Cloud is never configured, and its routes only mount when `FLIPPER_CLOUD_TOKEN` and `FLIPPER_CLOUD_SYNC_SECRET` are both set.
- Flags are checked lazily per request (`preload = false` in `config/initializers/flipper.rb`), so a request that never asks costs no query.
- Flipper caps actor gates at 100 workspaces per flag (`config.flipper.actor_limit`). A flag that needs more than that is ready to ship.
- Shipping a feature means deleting its constant and every check, then gating it with `Entitlements` if it is premium-capable, plus a migration that deletes its rows from `flipper_features` and `flipper_gates` (as `RemoveAiSreFeatureFlag` did when the agent shipped to every workspace).
- Tests run on Flipper's in-memory adapter, reset before every test. Turn a flag on with `FeatureFlags.enable!(workspace, flag)`.

## Identifiers

All callback_ids, action_ids, and subcommand strings are centralized in the platform-agnostic `Identifiers` module (`app/models/identifiers.rb`). Never use magic strings. Reference as `Identifiers::INCIDENT_CREATION_MODAL`, `Identifiers::SUBCOMMAND_CLOSE`, etc.

## Deploys

Firefight deploys many times a day, so every job and every long running path is written to be stopped part way and picked up again without anything left hanging or done twice.

### What a stopped worker does

A deploy sends TERM to the web and job containers, then kills them once the platform's grace period runs out.

- **Job workers** (`config.solid_queue.shutdown_timeout`, 25 seconds in `config/application.rb`). The supervisor stops taking jobs and gives the ones in flight 25 seconds. A job that finishes is done. One still running is either handed back (the worker deregisters, Solid Queue releases the claim and the same job, with the same `job_id`, runs again on the new version) or, when the supervisor's QUIT or the platform's KILL lands first, failed with `SolidQueue::Processes::ProcessExitError`, `ProcessPrunedError` (heartbeat stopped, found after `process_alive_threshold`, five minutes) or `ProcessMissingError`. Solid Queue never runs a failed job again on its own.
- **`InterruptedJob`** closes that gap. The recovery sweep puts every job failed with one of those process errors back on the queue, keeping its `job_id` and its retry counters, so an interrupted job runs again whichever way its worker stopped. The count is kept on the job's own arguments (`interruptions`). A job interrupted `InterruptedJob::GIVE_UP_AFTER` (3) times is taken to be what stops its worker, such as one that runs it out of memory. It stays failed, where the operator console shows it, and its class's `interrupted_too_often(*arguments)` is called once so whoever waits on it is told.
- **So every job must be safe to run again from the top.** Most are, by a guard on the row they change (a status moved by one guarded `update_all`, a checkpoint, a unique index, a lease). A job that makes a change Firefight cannot look up afterwards calls `notices_interruptions` (`ApplicationJob`): it notes its start in `job_runs` (`JobRun`) and clears the note when it finishes or raises, never when its thread is killed, so the same job starting again reads `interrupted_at` and knows an earlier run was cut off. It then ends what that run was doing with a plain reason instead of doing it again.
- **Web** (`force_shutdown_after 25` in `config/puma.rb`). Thruster passes TERM to Puma, which stops taking requests and lets those in flight finish for up to 25 seconds. Action Cable sockets close, and the browser reconnects to the new version (see Live updates below).
- **Health check.** `GET /up` is `Rails::HealthController`: 200 once the app has booted (production eager loads, so a class that fails to load fails the check), 500 otherwise. It does not touch the database, so a database blip never marks every web container unhealthy at once.

### Platform settings

| Service | Termination grace period | Health check |
|---|---|---|
| Web (`./bin/thrust ./bin/rails server`, port 80) | 45 seconds | Readiness: HTTP `GET /up` on port 80, initial delay 10 s, every 5 s, timeout 3 s, 3 failures. Liveness: the same path, every 10 s, 6 failures. Rolling deploy keeps the old containers serving until the new ones pass readiness. |
| Jobs (`bundle exec rake solid_queue:start`) | 45 seconds | None, it serves no HTTP. The supervisor replaces a worker process that dies. |

45 seconds is the 25 seconds work gets to finish, plus the supervisor's QUIT, deregistering and exit, with room to spare. Anything shorter than 30 cuts the worker off before it hands its jobs back, which still recovers (the sweep runs them again) but later.

### Recovery sweep

`RecoverySweepJob` runs every minute on the `events` queue, one at a time, and calls `InterruptedWork.recover!`:

- `InterruptedJob.run_again!`, above. A job class whose own recovery decides sets `runs_again_when_interrupted` to false and is left failed for it, which only `ConversationReplyJob` does.
- `Conversation::Recovery.sweep!` (docs/ai.md, Conversations): a reply job a stopped worker failed is run again once when nothing in the turn could have changed anything, and otherwise the turn is ended in the chat and its thread with "I was interrupted before I finished. Ask me again."
- `Investigation.abandoned` runs (lease ran out, or never claimed) get a new `InvestigationJob`. The claim decides, so a second job is harmless.
- `Conversation.reply_lost`, a turn still owed past `Conversation::REPLY_CEILING`, ends with `Conversation::Delivery::FAILED` in the chat and in Slack or on the page (`Conversation::Delivery.give_up_lost!`). `Conversation#drop_lost_reply!` clears the owed answer only while it is still the same one, so it is said once.
- `Conversation::HeldCalls.recover!`: a held call still checking after `CHECK_LOST_AFTER` gets its check job again (at most once a window, since the claim moves the row on), and one left running by a turn that will not run again ends with `COULD_NOT_FINISH`.
- `Postmortem.generation_stalled`, a draft generating past `GENERATION_STALE_AFTER`, ends failed with `GENERATION_INTERRUPTED`. The page says Firefight restarted while writing it and offers Try again, and the author is told in Slack, once (`Postmortem#give_up_generation!`).
- `IssueSyncService.give_up_lost_openings!`, an item still opening its issue after `OPENING_LOST_AFTER`, ends failed, saying to check the tracker before asking again.
- `WebhookDelivery.give_up_interrupted!`, a delivery still pending or in progress after `UNSENT_AFTER`, ends failed as `interrupted` on the webhook's delivery list.
- `ResourceMap::ReceivedEvent.give_up_interrupted!`, a map change still being read after `READ_LEASE`, is handed to the next full sweep as a failed re-read.
- `JobRun.forget_old!` drops run notes no job came back for.

Workflows have their own sweeper in the engine (docs/workflows.md, Recovery), since the app never names `SolidWorkflow`.

### Live updates

Nothing broadcast while a socket is away is sent again. The chat page (`use-agent-stream.ts`) reads the open chat again (`refreshOpenChat`) whenever its socket reconnects after a drop, so an answer that finished during a deploy shows without a reload, and it still reads it once after four seconds if the socket stays away mid answer. The investigation page polls while a run is live, so it needs nothing.

### Inventory

How long each kind of work runs, what a stop in the middle leaves, and why running it again is safe. "Again" is the same job run again, by Solid Queue or by `InterruptedJob`.

| Work | Runs for | Stopped part way | Safe to run again because |
|---|---|---|---|
| Chat turn (`ConversationReplyJob`) | Seconds to minutes | Handed back: the turn resumes from the saved chat. Failed: `Conversation::Recovery` runs it again once if it changed nothing, or ends it saying it was interrupted | `Chat#discard_interrupted_reply!` drops the half written reply, and `Chat#close_unfinished_calls!` closes a call left without its result as interrupted, so it is never run again. One turn per conversation (`limits_concurrency`) |
| Held call run (inside a turn) | Seconds | Again: the approval is single use, so the call cannot run twice. Given up or lost: ends `COULD_NOT_FINISH` | The gateway consumes the approval in one guarded update |
| Held call check (`HeldCallCheckJob`) | Seconds to a minute | Again: checks again (reads only). Lost: the sweep queues it again | `HeldCall#checked!` moves the row once |
| Investigation (`InvestigationJob`) | Minutes | The same job takes its run back at once (`claim!(by: job_id)`), steps still running are failed as interrupted, and the run continues from its saved turns | Lease and claim, turns written as they happen, `MAX_ATTEMPTS` then ends with a rerun button in the thread |
| Code fix step (`InvestigationFixJob`, a coding agent in the sandbox for up to 15 minutes, or one provider call) | Seconds to 15 minutes | Again (`notices_interruptions`): the step the cut off run had started ends at once with `LOST_TRACK` (check whether it went through) and is never called again, and the rest of the fix carries on. Lost: the job booked for `stale_after` ends it the same way | A change to someone's systems is never repeated without them. The sandbox is restored by the box's own trap, and `CodeBoxSweepJob` stops a box no run knows about |
| Fix state check (`FixStepCheckJob`), undo writing (`InvestigationUndoJob`) | Seconds to a minute | Again: reads or writes the undo again | `checked!` and `writing_undo?` guard the row |
| Workflow step (`SolidWorkflow::RunStepJob`) | Seconds (Slack calls) | Again: the step carries its job (`claimed_by`), so the same job takes up its own running step at once (`step.resumed` event). Lost: the sweeper resets it after `orphaned_step_threshold` | Every step that posts a new message is `checkpointed`, so a post that went out is not sent again. Narrow window: a kill after Slack answered and before the checkpoint or record was written can post twice, and `create_slack_channel` can make a second `name-<time>` channel |
| Postmortem draft (`PostmortemGenerationJob`) | Under two minutes | Again: written again (paid again). Lost: ended by the sweep with a plain reason and Try again | `start_generation!` is one guarded update, `generating?` guard |
| Issue sync (`IssueSyncJob`) | Seconds | Opening, again (`notices_interruptions`): never tried a second time, the item says to look in the tracker. Pushing: sets the same fields again. Lost: the sweep ends the opening | Trackers have no way to tell a second issue apart, so it is never opened twice |
| Webhook dispatch (`Webhooks::DispatchJob`) | Milliseconds | Again: adds only the deliveries still missing | Looks up deliveries for the event before creating |
| Webhook delivery (`Webhooks::DeliveryJob`) | Up to about 15 seconds | Again: sent again with the same `X-Webhook-Delivery` id and the next attempt number, never once it ended. Lost: the sweep ends it as `interrupted` | The stored signed payload is resent byte for byte |
| Domain events (`ProcessDomainEventJob`), Slack events (`ProcessEventJob`) | Milliseconds | Again: routed again. A message is recorded once (unique `message_id`), a file once | A mention handled twice can ask twice, only if the worker dies in the milliseconds between asking and finishing |
| Alert routing (`Alerts::RoutingSweepJob`) | Seconds | Rolled back with its transaction, routed again in two minutes | Row lock, `pending` check, advisory lock per signature |
| Map sweeps (`Integrations::MapSweepJob`, `MapEventJob`, `MapEventPollJob`, `MapEventSweepJob`) | Seconds to many minutes | Again or next run: connections already swept are skipped (`map_swept_at`), a change read left `reading` goes to the next sweep | `ResourceMap.record!` is one transaction, the poll cursor moves only after events are kept |
| Baselines and log patterns (`BaselineSweepJob`, `LogPatternSweepJob`, `LogPatternReadJob`) | Minutes to tens of minutes | Again: read again (costs reads, changes nothing twice) | Each write is a transaction |
| Halon regression case (`HalonRegressionCaseJob`) | Up to two hours | Again (`notices_interruptions`): settled as `LOST` at once. Never started: settled after `STALE_AFTER` | `claim!` stops a second replay, so nothing is paid twice |
| Approval notices and resumption (`AbilityApprovalNotificationJob`, `AbilityApprovalResumptionJob`) | Seconds | Again: the replayed request is guarded by `consumed_at` | Narrow window: a notice posted just before the worker died can be posted twice |
| Escalation nudge (`EscalationAcknowledgementReminderJob`) | Under a second | Again: a recorded nudge is not sent twice | Looks for the nudge event before sending |
| Short notices (`MemoryNoteJob`, `PackRefusalJob`, `PackRequestSettledJob`, `IncidentUpdateReminderJob`, `WorkspaceAiAccountNoticeJob`, `AiAccountAlertJob`, `SignupNotificationJob`) | Under a second | Again: posted again only if the worker died between the post and the end of the job | They finish well inside the 25 seconds a deploy gives |
| AI follow ups (`IncidentAiResponseJob`, `IncidentLearningJob`, `IncidentMistakeLearningJob`, `MilestoneNotingJob`) | Up to a minute or two | Again: asks the model again. Lessons and milestones are not duplicated | `Chat::Memory.learn!` dedupes, milestones keep a watermark |
| Recurring upkeep (cleanups, health checks, token refresh, registry refresh, search backfill, expiry, retention) | Seconds to minutes | Next run picks up where the data is | Each recomputes from the database. A token refresh cut off between the provider's answer and the save loses a rotated refresh token, a window only a kill inside that call reaches |

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

## Enforcement with ArchSpec

[ArchSpec](https://archspecrb.dev) checks the boundary rules in this document statically. The rules live in `Archspec.rb` at the repo root and run as the `Architecture: boundaries` step of `bin/ci`.

- Components are disjoint file sets (handlers, dispatchers, services, adapters, engines, entry points), plus namespace components for boundaries that are names rather than folders (`Slack::*`, `SolidWorkflow::*`, `AbilityGateway`, the integration clients).
- `ai.keys` (`AiKeysStayWithTheirAccount`): only `WorkspaceAiAccount#llm_context` and the engine build a RubyLLM context, and only `AiProviders` reads `RubyLLM::Provider`. A context copies the deployment's configuration, so one built anywhere else could carry Firefight's keys onto a workspace's call.
- The headline rules. Only `app/adapters/slack/`, the Slack webhook controllers, the OAuth install flow, and the `WorkspaceAdapter` factory may reference `Slack::*`. Only dispatchers reach handlers. Models never reference services, controllers, or adapters. The four entry points (Slack handlers, API, MCP, dashboard) never reference each other. Both engines keep their declared set of constants.
- `archspec_todo.yml` is empty and stays empty. Never add an entry to make a build pass: a new violation means the code is in the wrong place. The `archspec` GitHub job fails on any violation and on a non-empty todo file.
- ArchSpec sees constants and method calls, not strings or symbols. Duplicated query logic, raw table names in SQL, and magic strings are outside its reach and stay a review concern.
