# Workflows (SolidWorkflow)

Built on the SolidWorkflow engine (`engines/solid_workflow/`). The engine runs two kinds of workflow:

- **Class workflows**: Firefight's own flows (incident creation, close, update and the rest), a Ruby class per workflow whose steps are methods. They are thin orchestrators that delegate all logic to services.
- **Defined workflows**: a workspace's own, kept as data in versions and run by one interpreter class from a snapshot. See [Defined workflows](#defined-workflows) and [Workspace workflows](#workspace-workflows-app-records).

Read this before creating or modifying a workflow or touching the engine.

## Step DSL

```ruby
class IncidentCreationWorkflow < SolidWorkflow::Base
  workflow_name "incident.creation.v1"

  step :create_slack_channel
  step :set_channel_metadata, depends_on: [ :create_slack_channel ]
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

## Execution

- `start!(subject, context: {}, start_key: nil)` — async via background jobs (`RunStepJob`)
- `start_inline!(subject, context: {}, start_key: nil)` — synchronous (tests/console)
- Subject is a polymorphic AR object the workflow operates on
- **Idempotent start.** One `start_key` gives one run, however often it is started (a unique index on `solid_workflow_workflows.start_key`, and a lost insert race finds the winner). Without a key every start is a new run, as before.

## Orchestration

After each step completes, the engine finds newly ready steps (all dependencies succeeded/skipped, `run_at` passed) and enqueues them. Optimistic locking on `updated_at` prevents double execution of the same step.

## States

- **Step**: `pending → running → succeeded/failed/skipped/cancelled`, plus `waiting` (parked, see [Waiting steps](#waiting-steps)) and `bypassed` (on a route the run did not take)
- **Workflow**: `pending → running → succeeded/failed/cancelled/paused`, plus `waiting` when nothing runs or is ready and a step is parked. A waiting run is not stuck, so the stuck sweep leaves it, and it can be paused, cancelled and timed out like a running one.

## Retry

- Default: 5 attempts, exponential backoff (`2^attempt` seconds, capped at 300s)
- Strategies: `exponential` (default), `linear` (`attempt * 30s`), `fixed` (configurable or 60s)
- Per-step override via `retry_config: { max_attempts:, backoff:, backoff_seconds: }`
- A retry is booked for the moment its backoff ends (`Step#book_retry`, an `OrchestrateJob` at `run_at`), so it runs then rather than when the sweeper next finds the run. The claim's guard makes an early or doubled booking harmless.
- Being woken never uses up attempts. A parked step's wake gives back the attempt its claim counted, so a for each, sub workflow or event wait woken many times keeps its retries for real failures.

## Pause / Resume / Cancel

- `workflow.pause!(reason:, by:)` — running steps finish, no new steps enqueued
- `workflow.resume!(by:)` — resumes orchestration
- `workflow.cancel!(reason:, by:)` — permanent, cancels all pending/running/waiting steps and every run they started (sub workflows, for each items)

## Recovery

A deploy can stop a worker in the middle of a step (docs/architecture.md, Deploys). `RunStepJob` writes its `job_id` on the step it claims (`claimed_by`), and Solid Queue hands a stopped worker's job out again with the same id, so the same job finding its own step still running takes it up again at once, as another attempt, and records `step.resumed`. Any other job finds the step held and leaves it. A step only re-runs safely because every step that posts a new message is `checkpointed`: the post is kept on the step once it went out, so running the step again does not post twice. The window left is a stop after the platform answered and before the checkpoint was written.

`SweeperJob` handles the rest: resumes stuck workflows (idle >5min), resumes waiting runs a step was woken in while they could not move (`stalled`), resets orphaned running steps whose job never came back (idle >10min), wakes parked steps whose time came or whose signal arrived (`Step.due`, the backup for a lost `WakeJob`), ends attempts past their step's time limit (`Step.past_timeout`, the backup for a lost `StepTimeoutJob`), and fails timed-out workflows. An orphan moves with one guarded `update_all` on its status and the `updated_at` the sweep read, which also clears `claimed_by`, so a step its own job resumed in between is left to that job.

A step's job that finds its step moved on while it ran (cancelled, timed out, reset by the sweeper) drops its result quietly, since whoever moved it owns what happens next. A failure is recorded only on the attempt the job claimed (`mark_failed!(error, claimed_by: job_id)`), so a late attempt never fails the retry that replaced it.

## Held runs

A workflow class may hold its runs back: `runnable?(workflow)` on the class, true for every class workflow. A held run keeps its place. No step is claimed (`RunStepJob`), nothing is enqueued (`enqueue_next_steps`), no parked step is woken at its time (`WakeJob`), and the sweeper skips it. A signal sent to a held run is kept on the step, and once the run may move the sweeper picks it up and carries on. `DefinedWorkflow` holds every run of a workspace without the `WORKFLOWS` feature flag, see [The workflows flag](#the-workflows-flag).

## Event Timeline

Every state transition records a `SolidWorkflow::Event` (workflow-level and step-level). `workflow.timeline` returns the chronological audit trail.

## Defined workflows

`SolidWorkflow::Interpreter` (`lib/solid_workflow/interpreter.rb`) runs a workflow kept as data. `SolidWorkflow::Definition` reads and checks one:

```ruby
{
  "steps" => [
    { "id" => "step_k2f9", "name" => "check", "kind" => "wait_for_event", "config" => { "event" => "deploy.finished" },
      "timeout_seconds" => 600, "on_failure" => "stop", "retry" => { "max_attempts" => 3, "backoff" => "fixed", "backoff_seconds" => 10 } },
    { "id" => "step_p0x1", "name" => "decide", "kind" => "branch", "config" => { "routes" => [ ... ], "otherwise" => "no" } }
  ],
  "edges" => [ { "from" => "step_k2f9", "to" => "step_p0x1" }, { "from" => "step_p0x1", "to" => "step_z7c3", "route" => "yes" } ],
  "outputs" => { "outcome" => "{{steps.check.outcome}}" }
}
```

- **Snapshot at start.** `Interpreter.start!(subject, definition:, context:, start_key:, not_before:, parent_step:)` stores the definition on the run (`solid_workflow_workflows.definition`) and builds the step rows from it. Every step reads its spec from that copy, so editing the source never changes a run already going. A definition with problems is refused at start (`InvalidDefinition`), and `Definition#problems` lists them as sentences.
- **Stable ids.** A step's `id` never changes and is the engine row's `name`, which edges and `depends_on` use. Its `name` is what later steps refer to it by (`label` on the row), and may change between versions.
- **Edges and routes.** A step's incoming edges are stored on its row (`incoming`). An edge with a route carries on only when the step it leaves took that route (`Step#route`), an edge without one whenever that step succeeded. A step runs once every edge in is settled and one is live. It is bypassed when every edge in is dead, and so is everything only it leads to (`Step::Routing`, `Orchestratable#bypass_unreachable!`).
- **Failures.** `on_failure` is `stop` (the default, the run fails), `continue` (edges without a route carry on) or `error_route` (only edges with the `error` route carry on). A tolerated failure never fails the run.
- **Per step retries and timeouts.** `retry` is the class DSL's `retry_config`. `timeout_seconds` caps each attempt of a step that runs (`StepTimeoutJob` at `timeout_at`, then a failed attempt that retries while attempts remain), and is a deadline from first start for a step that waits (`TimeLimitReached`, never retried).
- **Data.** Before a step runs its config is filled from the run's scope by the host's `resolve`: `inputs`, `trigger`, `steps` (each succeeded step's output by its name) and, inside a for each, `item` and `index`. The filled config is the step's stored `input`. Inputs, outputs and signal payloads pass through the host's `clean` before they are stored. A run's `result` is its `outputs` filled, or every step's output by name.
- **Host hooks** (class methods on the subclass): `action_kinds`, `perform(kind, config, workflow:, step:)`, `resolve`, `clean`, `start_sub_workflow`, `runnable?`, `observe(workflow, event)` (told of every event the run records), `result_of`, `stand_in(step, workflow:)` (an output, or a `Routed` with its route, used in place of running the step, nil to run it, asked before every step runs).

### Control steps

| Kind | Config | Does |
|---|---|---|
| `branch` | `routes: [{ route:, when: }]`, `otherwise` | Takes the first route whose condition holds, or `otherwise`. If and else is one route plus otherwise, a switch is several routes. Conditions (`SolidWorkflow::Condition`) compare `left` and `right` with `equals`, `not_equals`, `is_one_of`, `contains`, `starts_with`, `matches_regex`, `is_empty`, `is_not_empty`, `greater_than`, `greater_or_equal`, `less_than` or `less_or_equal`, combined with `all`, `any` and `not` |
| `delay` | `seconds`/`minutes`/`hours`/`days`, or `until: "09:00"` with `time_zone`, or `at` | Parks until then. The time is worked out once and kept in the step's checkpoint |
| `wait_for_event` | `event`, `key`, and the step's `timeout_seconds` (required) | Parks on the signal key `event:key` until `SolidWorkflow.signal!(key, payload)` or the deadline, and takes the `received` or `timed_out` route. Output `outcome` and `event` (the payload) |
| `for_each` | `items`, `concurrency` (default 1), `steps`, `edges`, `outputs` | Starts one child run per item from the steps inside, at most `concurrency` at once, each child that ends waking the loop to start the next. Output `count` and `results` in item order. An item that fails ends the loop and cancels the rest. A child's `context.iteration` names its place in every loop it sits in |
| `join` | `mode: all` or `first` | `all` waits for every route in and hands on each live one's output by name. `first` runs as soon as one route in arrives |
| `run_workflow` | `workflow`, `inputs` | The host starts the named workflow as a child run (`start_sub_workflow`) and the step takes its result. A child that fails fails the step |

**Once at.** `start!(..., not_before: time)` starts the run waiting, its first steps parked until the time.

### Waiting steps

A step that waits is parked, not held by a worker: status `waiting`, `run_at` for a time, `signal_key` for an event. `WakeJob` wakes it at `run_at`, and only once it is due. `SolidWorkflow.signal!` hands the payload to every step waiting on the key. A child run that ends wakes the step that started it (`Workflow#transition!` into a terminal state). Waking moves `waiting → pending` in one guarded update, so two wakes move it once. A wake that lands while the step is still running is counted (`wake_requests`), and the step wakes itself as soon as it parks, so it is never lost. A signal reaches only a step already waiting for it.

## Workspace workflows (app records)

The app keeps its own records, which outlive the engine's 30 day cleanup. Model logic lives on the models, starting a run is `WorkflowRunService`, and `DefinedWorkflow` (`app/workflows/defined_workflow.rb`) is the interpreter subclass the engine runs them with.

| Record | Holds |
|---|---|
| `Workflow` | workspace, name, slug, other names (`aliases`, found like a runbook's with `Workflow.named`), description, owner team (a catalog team entry), on or off (`enabled`), `agent` (the machine principal its runs act as, nil until one is made for it), `cost_cap_cents` (nil means no cap), `live_version`, `next_run_at`, `freeze_behaviour`, `runs_per_hour`, `subject_key`, `all_clear`, `library_key` and the rest of [Firefight's library](#firefights-library), `origin_conversation` (the chat Halon made it from), `trigger_refusal` |
| `Workflow::PublishRequest` | a member asking the admins to publish a workflow's draft: `requester`, `version`, `requested_at`, `published_at`/`published_by` or `dismissed_at`, the direct messages it sent (`notifications`) |
| `Workflow::Version` | trigger, steps, edges, outputs, `number`, `status` (`draft`, `live`, `retired`, `discarded`), `revision`, author (`author_kind` person or halon, `author`), `reason`, `parent_version`, `published_at`, `published_by` |
| `Workflow::Edit` | one operation (`add_step`, `remove_step`, `move_step`, `connect`, `disconnect`, `change_config`, `change_trigger`, `rename`) with its `payload` and `targets`, author, Halon's `reason` (required for Halon), `base_revision` and `applied_revision`, `status` (`applied`, `proposed`, `accepted`, `dismissed`), `change_set_id`, `source_run`, `source_chat`, `decided_by` |
| `Workflow::Run` | workflow, version, `trigger_kind`, `trigger_payload`, `inputs`, `outputs`, `start_key`, the `agent` it acted as, who started it (`started_by_kind`, `started_by`), `parent_run` and `parent_step_key` for a sub workflow, `status` (`queued`, `running`, `waiting`, `paused`, `succeeded`, `failed`, `cancelled`), `error`, `pinned`, `details_pruned_at`, `test` and `real_step_keys`, `subject_key`, `told_at`, `telling_job_id`, timing |
| `Workflow::Run::Step` | per step and per for each item (`iteration`): status, route, input, output, `saved_result_ids`, `invocation_ids`, attempts, error, timing. Owns the chat a Halon step, a read before a change or a watch keeps |

- **Versions.** One live, at most one draft (partial unique indexes). `Workflow#open_draft!` opens the draft from the live version. `Version#publish!(by:, revision:)` retires the live version and promotes the draft in one transaction, guarded on the revision the publisher saw. A published version never changes. `restore!` makes a new draft from an old version. While a draft is open it is refused with `restore_blocked_reason`, "Publish or discard the open draft first." `problems` is what publishing checks: the trigger, the engine's definition problems, and every reference pointing at an input that exists or a step that runs before it.
- **Edits.** `Workflow#edit!(operation:, payload:, by:, halon:, reason:, base_revision:)`. Each lands with one `update_all` guarded on the draft's revision (`Version::Drafting`). An edit made on an older revision lands on top when nothing it touches changed since, and is refused naming who changed it otherwise. A new step gets its stable id before the edit is recorded. Renaming a step rewrites every `{{steps.old...}}` reference. Renaming the workflow (a rename with no step) changes its name at once.
- **Halon's edits.** Applied directly only while Halon builds a workflow alone (nothing live, no draft a person touched). Otherwise each is a proposal, grouped by `change_set_id`, which `Edit#accept!` applies to the draft and `dismiss!` drops, both guarded so two people deciding at once decide once. `workspaces.halon_applies_workflow_read_fixes` (default off) says whether Halon may apply its own repairs to steps that only read, and nothing reads it yet.
- **Data passing.** `Workflow::Version.filled(value, scope)` fills `{{inputs.x}}`, `{{trigger.x}}`, `{{steps.name.field}}`, `{{item}}` and `{{index}}` through `Placeholders`, the logic `Runbook.filled` uses: a lone reference keeps its type, one naming nothing reads as empty. `Workflow::Run#kept` redacts anything shaped like a credential (`Chat::SecretFree.redacted`) on the way in and out, and keeps an answer over 16 KB whole as a `Chat::SavedResult` owned by the run, leaving its short plain fields and a `saved_result` reference in the step's data.
- **Run records.** `DefinedWorkflow.observe` writes a step's row whenever the engine records an event for it, every step's row on run level events, and the run's status from its engine state (`DefinedWorkflow::RUN_STATUSES`, where a run an operator paused is `paused`, apart from `waiting`). A run's status moves with one guarded update and never leaves a finished state, except a failed run an operator took up again.
- **Who a run acts as.** The workflow's own `agent`, copied onto the run when it starts, whoever started it, apart from a test run (below). See [The workflow's own identity](#the-workflows-own-identity).
- **Retention.** `workspaces.workflow_run_retention_days` (90 by default, 1 to 400) is how long a finished run keeps its details. After it `WorkflowRunRetentionJob` (daily) drops them through `Workflow::Run#prune_details!`: the step rows with their inputs and outputs, the run's saved results, and its inputs, outputs and trigger payload. The run row stays for good as the run's one line, when it ran, its trigger kind, version, status and the agent it acted as, with `details_pruned_at` set. A run that is queued, running, waiting or paused is never pruned, and a pinned run (`pinned`) keeps everything. The claim is one update guarded on the run being finished, unpinned and whole, so a run an operator takes up again or a person pins in between keeps its details, and the engine's later moves never write onto a pruned run. The engine's own rows for a run go after 30 days, as every run's do.

### Step kinds

Each kind a step can be is one class under `app/workflows/defined_workflow/steps/`, listed in `DefinedWorkflow::Steps.kinds`. A kind says its `label` and `group`, what its config holds for an agent writing one (`config_help`), whether it `changes?` (decided by what it calls, never by the author), whether a change of it is `undoable?` (and so needs `config.undo`), whether it `checks?` (reads how something stands, so it can follow a change), the `output_fields` later steps may read, its config `problems`, its `reach` (what the workflow's identity needs granted to run it, `DefinedWorkflow::Reach::Needed`) and `describe` for a page. `DefinedWorkflow.perform` runs a kind the app defines, the engine runs `branch` and `delay` itself. Adding a kind is its class and a line in `kinds`.

| Kind | Config | Does |
|---|---|---|
| `call_tool` | `tool`, `arguments`, `undo` | Any tool Halon can call, through the same `Chat::Tools.catalog` entry a chat gets, run on a `Workflow::AgentRun` (the duck type the chat's tools ask of whoever they run for). Output `answer` and `data` (the answer read as JSON). Reads or changes by `DefinedWorkflow::Reach.changes?` (a capability's own `writes`, else `Chat::Tools.kind`, with a read guard shown only what is written out) |
| `ask_halon` | `question`, `data`, `fields` | One structured call (`FirefightAi::WorkflowAnswer`) answering `verdict` (ok, problem, unsure), `summary` and each field. Reads |
| `run_skill` | `skill`, `focus` | `FirefightAi::SkillFollower` follows one skill with only the tools `use_skill` would hand over, on a reads only `Workflow::AgentRun`, and ends with `report_step`: `verdict`, `summary`, `severity`, `findings`, and `problems` (always a list, empty when none), each problem that needs a person with its `topic` (the same each time for the same problem), `summary`, `severity`, `resource` and `due_on` (a `YYYY-MM-DD` day, dropped when the model gives anything else, since `raise_notice` refuses a day it cannot read), so a for each can raise one notice for each. Reads, whatever the skill's tools could do |
| `watch` | the `start_watch` spec | Starts the same `Chat::Watch` a chat keeps (`Conversation::Watches.start` with a `Workflow::WatchHost`), on a chat owned by the step's row, as the run's identity. The watch reports to nobody as it goes, and its end is delivered to the step, which takes the route named for it (`succeeded`, `failed`, `timed_out`, `stopped`) |
| `post_to_channel` | `channel` or `reply_in_chat`, `message` | Firefight's `post_to_channel`, or back where the workflow was made from a chat (`ChannelPostService#reply!`: its thread, or the person's direct messages). Changes, no undo, no freeze or read first |
| `raise_notice` | `signal`, `topic`, `summary`, `severity`, `due_on`, `resource` | `Investigation::Notice.observe!` with the run, said through `Investigation::NoticeDelivery` in the resource's team channel, else the workflow's team, else the monitoring channel. A resource not on the map is kept as it was named (`resource_words`) and the notice names it in words, so the notice is still raised, and it is one problem per resource so named and topic (`Investigation::Notice.key_for`). Authorized as `monitoring.create`, never held. Changes, no undo |
| `investigate` | `incident` or `symptom`, `names` | Starts an investigation through `InvestigationService` (trigger source `workflow`), authorized as `investigations.create`, or waits on the one already running for the incident. Parks on `Investigation#finished_signal`, which `Investigation#finish!` sends through `WorkflowSignalJob` and `DefinedWorkflow.signal!`, and looks again every five minutes. Outputs status, finding, confidence (the winning hypothesis's), suggests_incident, url. Reads |
| `classify` | `data`, `routes`, `guidance`, `otherwise` | One structured call, as Ask Halon makes (`WorkflowHalonStepJob`), asked for a `route` among the routes, and takes it, or `otherwise` (`other` by default) for an answer naming none. Each route is a way out on the canvas. Reads |
| `open_incident` | `name`, `summary`, `severity`, `type`, `fields`, `undo` | `declare_incident` with the declare form's answers. Hands on `incident`, its identifier. Changes, with undo |
| `update_incident` | `incident`, `change` and what it sets | One change a step: status, severity, type or fields through the update form (`post_incident_update`, with the step's message or one naming the workflow), lead or a role (`assign_incident_role`), invite (`invite_responders`) or runbook (`attach_runbook`). Changes, with undo |
| `post_incident_update` | `incident`, `message`, `every_minutes` | `post_incident_update` with the message, once, or again every few minutes while the incident is live: the count and the next time are kept in the step's checkpoint, the step parks between, and it ends once the incident is resolved or cancelled. Changes, no undo, no freeze or read first |
| `page_on_call` | `incident`, `reason`, `target`, `tool`, `person`, `escalate_to` | Reads who the on-call tool has on call (`Integrations::Paging`, through the gateway as the identity, needing that connection's read pack), then `page_on_call`, or `escalate_incident` to `escalate_to` when no on-call tool is connected. Changes, no undo |
| `create_follow_up` | `incident`, `description`, `member`, `kind`, `open_issue`, `undo` | `create_action_item`, then `create_action_item_issue` when `open_issue`, each its own call. Changes, with undo |
| `message_person` | `to` (person, lead, role, on_call), `person`, `incident`, `role`, `message` | One `channel_posts.create` call for everyone it reaches, then `ChannelPostService#tell!` to each in their direct messages. on_call is `Incident#on_call_members`. Changes, no undo |
| `status_page_update` | `tool`, `arguments`, `undo` | A Call a tool limited to tools that change something on a connection whose provider the registry marks `holds_status_pages`. Changes, with undo |
| `branch`, `delay` | as above | The engine's own |

The kinds that call one of Firefight's own tools chosen from their config are `DefinedWorkflow::Steps::FirefightTool`s: a kind says `tool_for(config, workspace)`, `arguments_for` and what it hands on, and gets the Call a tool step's gateway call, approvals, freeze, read first and test run pretending. A field of a kind's settings may say `shown_when` (another field and the values it must hold), so Update incident asks only what its change needs and a hidden field's value is not sent.

- **Work handed off.** A step whose work takes long, Halon or reading how things stand, hands it to a job and parks (`Base#await`): the name is marked asked once in the step's checkpoint with the time (`DefinedWorkflow.mark_asked!`), the job delivers its answer with `DefinedWorkflow.deliver!` (once, by name, in one statement) and wakes the step, which reads it on its next attempt. With nothing delivered within the step's time limit (30 minutes when it sets none) of handing it off, it fails, so work handed off late, such as a read after a long approval, gets its full wait. Each retry of a step asks under its own name (`name#try<n>`, counted from the engine's retry events), never reading what the try before it got back. An error in the Halon job that nobody expected is handed to the step in words. `deliver_for_record!` finds the engine's step from the run's row, for a watch.
- **Refused and failed.** `Base::Refused` is a step's own words for why it cannot go on and is never retried. `Base::Failed` is what it called failing. A step acts once unless its own `retry` says otherwise (`DefinedWorkflow.default_retry_config`). A step's error is stored without the class the engine writes ahead of it (`DefinedWorkflow.error_words`).
- **Every call through the gateway.** `Workflow::AgentRun#tool_call` runs `Chat::ToolCall.run!` as the run's acting principal with source `workflow`, `triggered_by_label` naming the run, and the run and its step (`Workflow::Run::Step.ledger_context`: `workflow_run_id`, a column on `ability_invocations` and `ability_approvals`, `workflow_step_key`, the step's id, and `workflow_iteration`), as does the read before a change (`WorkflowStateCheckJob`). `Workflow::Run::Step#invocations` reads a step's rows, and `waiting_approval?` is a waiting step whose held call's approval is still pending, which the canvas shows as Waiting approval. `run.invocations` is every call of the run.
- **Approvals mid run.** A change an approval rule holds parks the step (`ApprovalResumption.park_workflow_step!`, kind `workflow_step` with the engine step and its key). The decision is delivered to it. Approved, it reads how things stand again (below) and runs exactly that call with the approval. Declined, it fails and takes its error route when it has one. Undecided within its time limit (24 hours by default) the approval expires and the step fails saying so.

### Running safely

- **Test runs.** `WorkflowRunService#start!(test: true, real_step_keys:)` runs the draft, or the live version when there is none, as the person testing (`Workflow::Run#acting_principal`). Reads run for real. A change only shows what it would do (`simulated`), unless its step is among `real_step_keys`. A test run counts against no limit and says nothing when it ends. It also takes outputs pinned on the draft in place of their steps, and `up_to` for one step. See [Trying a draft](#trying-a-draft).
- **Freeze windows.** A change inside a window `Workspace::FreezeWindows.covering` finds stops the run with the freeze's sentence, or parks until the window ends when the workflow says `freeze_behaviour` `wait`. `Workflow#freeze_warning` says when the next scheduled time lands in one.
- **Read before a change nobody pressed.** In a run a Schedule, Once at or event trigger started (`Workflow::Run#reads_first?`, `Workflow::Run::Acting::UNATTENDED`), a change first hands `WorkflowStateCheckJob` the call, which runs `Chat::StateCheck` as the run's identity on a chat owned by the step's row. Anything but unchanged stops it, with `Chat::CurrentState::WORDS`. The same check runs again after an approval.
- **Every change carries its undo and ends with a check.** Publishing (`Workflow::Version#problems`, `Version::Steps`) refuses a step that `undoable?` with no `undo`, and one with no step that `checks?` running after it.
- **Limits.** `runs_per_hour` (60 by default, `rate_blocked_reason`), one live run per subject when `subject_key` names one with a reference to the inputs or the trigger (`subject_for`, a partial unique index on open runs), and, for runs an event starts, `workspaces.workflow_event_runs_per_hour` across the workspace (`Workflow.event_blocked_reason`). Both are counted with the workflow's row locked, and the workspace's for an event, until the run is made, so starts at once cannot each see room for one more. `cost_cap_cents` caps each run's AI: `Workflow::Run#ai_spent_cents` counts every inference of the run and its steps, and a Halon step gets what is left (`Workflow::HalonStep#room_cents`), or nothing and fails when it is spent.

### Triggers

`Workflow::Trigger::Schedule` reads a Schedule or Once at trigger in its own `time_zone`: `repeat` every few `minutes` (5 to 720, counted from the start of the day) or `hours` (at a minute), on `days` of the week `at` a time, or `monthly` on the first to fourth or last weekday. Once at is `at`, a local date and time, at most a year ahead. `next_after` works out the next time, `words` says it. A published workflow starts on a kind in `Workflow::Trigger::PUBLISHABLE`, and any other kind is refused when publishing.

#### Something happening

The kinds in `Workflow::Trigger::EVENTS` start when something happens. Where it happens says so with `Workflow::Trigger::Events.fire!(workspace, kind, key:, subject:, details:, actor:)`, which, after the change commits and only while a live, switched on workflow of that kind exists in a workspace with the flag (`Workflow.listening`), enqueues `WorkflowEventJob`. `fire!` never raises, logging its own failures, so telling workflows never stops what happened from finishing. The job hands it to `WorkflowTriggerService#heard!`, which builds the run's trigger data and the fields its conditions read (`Workflow::TriggerPayloads`) and starts every workflow that hears it (`Workflow#hears?`, `Workflow::Listening`) through `WorkflowRunService`, as `started_by_kind` trigger with the start key `event:<kind>:<key>`, so one event starts a workflow once however often it is heard. A start its limits refuse is kept on the workflow (`trigger_refused!`), as a scheduled start's is.

| Kind | Fired from | Key | Trigger data |
|---|---|---|---|
| `incident_declared` | `Workflows::EventSubscriber` on `incident.created` (`EventRouter`) | the timeline event | `incident` and `actor` as outbound webhooks send them |
| `incident_changed` | the same, for any event `Workflow::Trigger::Changes.incident` names: status, severity, type, lead, role, custom field, accepted, resolved, reopened, cancelled, escalated | the timeline event | `incident`, `actor`, `change` (what changed) and `changes` (each named field before and after, by name) |
| `follow_up_changed` | the same, for a follow up created or completed and a postmortem started or completed (`Changes.follow_up`) | the timeline event | `incident`, `actor`, `action` or `postmortem`, `change` |
| `alert_received` | `AlertIngestService#route`, after routing commits | the alert | `alert`, `outcome` (the routing action, or `unmatched`), `incident` |
| `notice_raised` | `Investigation::Notice.observe!`, when a notice is new (raised) or news again (worsened) | the notice with its severity, due date and when it was last said | `notice`, `change` |
| `investigation_finished` | `Investigation#finish!`, for one that concluded or gave up, never a rehearsal or one a person stopped | the investigation | `investigation` (finding, confidence from the winning hypothesis, question, url), `incident` |
| `run_failed` | `WorkflowRunEndService#ended!`, for a real run that failed and no other workflow ran | the run | `run` (workflow, error, failed step, url) |
| `deploy_finished` | `Integrations::MapEvents.report_runs_ended!`, from both event addresses, for each run a connection's event source says ended (`Integrations::RunsEnded`, a source's `runs_ended`) | the provider and its own id for the run, one per attempt | `run` (kind deploy or ci, outcome succeeded, failed or cancelled, name, place, ref, commit, environment, url, connection) |
| `resource_changed` | `ResourceMap::Change` once it is committed: appeared, removed, deployed, status changed, renamed, configured | the change | `change` (kind, from, to, detail, words) and `resource` |
| `security_event` | `SecurityEventJob`, before the security module looks into it, whether or not it does | the provider, kind and reference | `event` (kind, what, place, url, public) |
| `issue_assigned` | `Conversation::IssueSessions#receive!`, when a tracker hands an issue to Firefight, beside Halon taking it up | the connection and session | `issue` (key, title, url, text, who asked) |
| `inbound_webhook` | `Api::V1::WorkflowHooksController`, a signed POST to the workflow's own address (below) | the sender's `X-Firefight-Delivery`, else the body's digest | `body`, `received_at`, `delivery` |

- **Once per group.** An alert is heard when routing lets it through and it did not join a group already open, so a storm of one alert starts one run. A dropped alert starts nothing.
- **Conditions.** A trigger's `conditions` are the rule engine's (`field`, `operator`, `value`, matched by `Policy::Conditions`, which `Policy::Evaluation` uses too), and every one must hold. Each kind says what they may read and the workspace's values for each (`Workflow::TriggerKinds::Kind#conditions`). An incident's are its severity, type and status by slug, its stage, where it was declared from, whether it is private or a test, its lead's email and each custom field as `fields.<slug>`, and an alert's are its normalized fields with the catalog's related entries and attributes (`Policy::ContextBuilder`). Only a kind something happening starts may hold conditions, at most 20, checked when publishing.
- **Choosing changes.** `incident_changed` and `follow_up_changed` hold `changes`, the changes that start them, required and checked against `Workflow::Trigger::Changes`.
- **Never itself.** An event carries who caused it (`actor`), and a workflow never hears an event its own identity caused, so a change a workflow makes never starts that same workflow again. A run that fails is never heard by its own workflow, and a notice a workflow's run raised is never heard by that workflow.
- **The workflow's own address.** Every workflow has a `hook_token` (`Workflow::Hook`), and `POST /api/v1/workflow_hooks/:token` starts it when its live trigger is an inbound webhook, it is on and the workspace has the flag, and answers not found otherwise. The body is a JSON object of at most 100 KB, signed as outbound webhooks are: `X-Firefight-Timestamp` and `X-Firefight-Signature` `v1=<HMAC-SHA256 of v1:<timestamp>:<body>>`, within five minutes either way. The secret is never stored: it is an HMAC of the workflow's id and token under a key derived from the app's secret (`hook_secret`), so `replace_hook!` replaces the address and the secret together. `WorkflowTriggerService#hooked!` starts it (202 with the run id), says nothing started when the conditions do not hold (200), and hands back a refusal from its limits (409), kept on the workflow as any trigger's is. Conditions read the body as `body.<path>`, four levels deep. The canvas shows the address to anyone who opens it, and someone who may change the workflow copies its secret (`WorkflowHooksController#secret`, fetched on demand) and replaces the address after asking (`#replace`, with a toast).
- **Every provider by its source.** A deploy or CI run ending is a source's `runs_ended(payload, headers:)` answering `Integrations::RunsEnded::Run`s, only for runs that ended (a GitHub workflow run that completed and a deployment status of success, failure or error, a GitLab pipeline or deployment that succeeded, failed or was cancelled, a Bitbucket build status that is successful, failed or stopped, a Netlify deploy that published or failed). A source that answers nothing reports none. The map records no scaling, so a resource scaled starts nothing unless its provider reports it as a setting that moved, and a tracker labelling an issue is not reported.
- **Limits.** Every event start counts
 against the workspace's `workflow_event_runs_per_hour` (100 by default), the workflow's own runs an hour and its one live run per subject, through `WorkflowRunService`.

`Workflow#next_run_at` holds the next time, set when it is published or switched on and cleared when it is switched off (`Workflow::Scheduling#schedule!`). `WorkflowTriggerSweepJob` (every minute) takes each due workflow with `claim_due!`, one statement naming the time it was due, and starts a run with the start key `trigger:<time>`. A start its limits refuse is kept on the workflow (`trigger_refusal`) for its page, and so is one that broke, which never stops the sweep reaching the workflows after it. A start that broke has its due time given back so the next sweep tries it again under the same start key (`release_due!`), for `RETRY_FOR` (15 minutes). After that the time is given up: the sweep keeps it as a run that failed to start (`GAVE_UP`, under that time's start key), which `WorkflowRunEndedJob` says like any failed run, in the owning team's channel or to whoever published it, and the next scheduled time, which the claim already moved to, runs as usual. Giving up that itself breaks is kept on the workflow (`given_up_at`, `keep_given_up!`) and the next sweep records and tells of it again, telling once (`claim_telling!`), so the time stays given up and never runs late. A one off is done only once a real run ran, never after a test run alone. A one off has no next time once it ran, and is then listed as done.

### The workflow's own identity

An `Agent` made with the workflow (`Workflow#ensure_agent!`, named "<name> workflow", slug `workflow_<slug>`) holds only what was granted to it. It is never listed or managed on the Agents screen, over the API or MCP, and never holds a token (`Agent.standalone`, `ApiKey#not_a_workflows_own`), but it is a principal on the Permissions screen like any agent. `Workflow::Version#reach` reads what its steps need: a connection's read pack for a read through it, the one ability for a change, a system ability for Firefight's own tools, and `map.read` for anything routed through the map. `Workflow#standing` says which it holds.

`WorkflowPublishService#publish!` makes the draft live, grants the identity what it does not hold yet (as the publisher, every environment), and schedules it, in one transaction, then settles every request to publish it. Publishing is `workflows.update`, and granting is `permissions.create`, which the controller and the Slack button authorize. A member holds `workflows.create` without a grant (`Ability::Action::WORKFLOWS_CREATE`, "Make workflows", one of `WorkspaceMembership::NARROWABLE_KEYS`, ledgered unlike participation), which a grant narrows and No access takes from one member, like the map and asking Halon, and which the Permissions screen offers only where workflows are on: they make drafts, test them and run published workflows, and ask the admins to publish (`Workflow::PublishRequest`, once a day per member and workflow like a pack request, a direct message to every admin with Publish, and the Workflows page lists what waits). Publish on a request publishes the draft at the revision the admins were asked about (`PublishRequest#revision`, `stale_reason`) and refuses one changed since, and the publish dialog sends back the revision it showed. The `workflows` ability is hidden from grants without the flag (`Ability::Action.hidden_resources`), on the screens and in what a key's or agent's matrix may hold (`Ability::Grant.replace_system_grants!`). A skill step's reach is only the reads of the tools its skill names, whatever else those tools could do. Without the flag every workflow page answers not found before anything checks who is asking (`RequiresWorkflows` runs first).

### When a run ends

`DefinedWorkflow.observe` enqueues `WorkflowRunEndedJob` when a run reaches a finished state. `WorkflowRunEndService` stops any watch its steps still keep, and, once per run (`claim_telling!`), for a run neither a test nor another workflow's:

- **A failed run** is said in the owning team's notification channel from the catalog, else to whoever published the version by direct message (`post_workflow_failure`), and to them too when the team channel is gone, archived or does not have Firefight in it. It counts as told (`told_at`) only once it lands. The job telling it holds the run (`telling_job_id`), so a job its stopped worker left, which `InterruptedJob` runs again with the same id, takes its own claim back. Anything that breaks while telling gives the claim back (`Workflow::Run#release_telling!`), and after a platform error `WorkflowRunEndedJob` tries again, waiting longer each time, up to 20 tries, with the fix Halon already suggested rather than a new one. A workflow with nowhere at all to tell stays untold. First Halon reads why the failed step failed (`FirefightAi::WorkflowRepair`) and, when its settings caused it, suggests a change as a proposal on the workflow with its reason and the run, which the run's and the workflow's pages show with Accept and Dismiss. Halon looks once per kind of failure for each published version: the failure is keyed by the failing step and its error's words with numbers, times and ids taken out (`Workflow::Version.repair_problem_key`), every key seen is kept on the run's version (`repair_problem_keys`), and a run failing in a way already looked at spends nothing, however failures take turns (`claim_repair!`, one guarded update). A failure at another step or with other words is looked at once too. Publishing a new version starts with none, so every failure is looked at again after the workflow changes. A look that broke before Halon answered, such as a model call that timed out, is given back (`release_repair!`), so the same failure is looked at on the next run.
- **An all clear**, for a workflow with `all_clear` on (off by default, including the library's), is one line in the same place when the run succeeded and raised and posted nothing.

### Templates

Besides its items ([Firefight's library](#firefights-library)), `Workflow::Library` holds templates, built from a few answers rather than kept as data: `check_later` (Once at, reads a resource's status and its key reads against normal, Ask Halon judges, Post to channel or back to the chat) and `probing_scan` (every weekday at 09:00, each connected edge network's security events through a skill with the `security_events` signal, then the `probing_scan` skill, a branch on its verdict and a probing notice). `create!` makes a draft from one, attributed one edit at a time. A workflow made from a template is the workspace's own, with no `library_key`, since nothing moves it on.

### The pages

Under Halon, Workflows (`WorkflowsController`, `/halon/workflows`), in four tabs: the workflows, every run, the one offs that are done with their runs and Repeat it, and Library ([Firefight's library](#firefights-library)). Each row opens the workflow's page, which is its canvas ([The canvas](#the-canvas)): its steps, Halon's suggestions, its versions, what its identity can do and its settings, Run, Publish or Ask an admin, On or Off, and Delete under its settings. A run's own address (`WorkflowRunsController#show`, which Slack, the chat card and the Workflows page link to) opens it on the canvas ([A run on the canvas](#a-run-on-the-canvas)). Settings, Workspace holds how long runs keep their details (`WorkflowSettingsController`). Every page answers not found without the flag (`RequiresWorkflows`, which every workflow and skill controller includes and which runs before anything checks who is asking), and the sidebar shows Skills and Workflows only with it (`workflowsEnabled`).

### Halon, MCP and the chat card

- **Written whole.** `Workflow::Authoring` takes a workflow as an agent writes it (`schema`, one shape for Halon and MCP): a name, a trigger (a Once at trigger may give `in_minutes`, read in the writer's time zone), steps by name and edges by name, or a library `template` with its `params`. `preview` says what it would be without making anything (the confirmation's rows, its moments written as `Chat::TimeToken`s, which the dashboard shows in the viewer's time zone with the zone named and Slack as `<!date>` in each reader's), `create!` makes the draft one attributed edit at a time and refuses one that could not be published, rolling it back.
- **Halon's tools** (`Conversation::Tools::CreateWorkflow`, `RunWorkflow`, `ListWorkflows`, offered only with the flag). Making and running one is confirmed on the card first (`Chat::Tools.planned`: when it runs, each step, what it will be able to do, the inputs). A timed trigger or a template Halon gives without a time zone takes the asker's when the call is asked (`Chat::Tools.settle_asked!`, `CreateWorkflow.settled_arguments`), kept in the call, so every card and the workflow made read its time as the same moment. Made by someone who may publish (`WorkflowPublishService#may_publish?`: `workflows.update`, and `permissions.create` when it needs grants), it is published, each through the gateway as the asker. Anyone else's waits as a draft and a member asks the admins (`ask_or_leave!`). Publishing goes through `WorkflowPublishService#publish_through_gateway!`. Publishing an approval rule holds leaves the draft made and says so (`PUBLISH_HELD`), never asking for a retry, which would make a second workflow: the approval is parked with the draft's revision (`ApprovalResumption::KIND_WORKFLOW_PUBLISH`, which call it held in `stage`), approving it publishes exactly that revision as whoever asked (`publish_approved!`), and approving one whose draft changed since is refused with why (`Ability::Approval#approve_blocked_reason`, `Workflow.publish_approval_blocked_reason`). It runs as the workflow's own identity, started by Halon for the person. With the flag, `make_plan` refuses a later time (`LATER_IS_A_WORKFLOW`), so anything later or repeating is a workflow and there is one scheduler. Plans already scheduled run as before.
- **The chat card.** A workflow made from a chat keeps it (`origin_conversation`). Its last run is never a test run (`last_chat_run`). The dashboard chat draws it after the turn that made it (`AgentChatWorkflowSerializer`, the `workflows` prop, the `workflow` stream event) with Run now, and Cancel for a one off or Turn off for one that repeats (`Workflow::Chatting#chat_offers`, each with its blocked reason on its own button: running needs `workflows.create`, stopping is for whoever made it or someone who may change a live workflow). A chat in a thread keeps a message there with the same buttons (`Slack::Messages::ChatWorkflow`, `Interactions::ChatWorkflowHandler`), redrawn by `ChatWorkflowMessageJob` whenever it moves (`Conversation::Workflows.moved!`: made, run, ended, stopped). A Post to channel step with `reply_in_chat` posts the result back there.
- **MCP** (`list_workflows`, `create_workflow`, `run_workflow`, `update_workflow_settings`, each `behind_flag`): `Mcp::Tools.available_in` leaves a tool behind a flag out of the server's list, Halon's catalog and runbook step choices, and the dispatcher refuses a call to one. The MCP versions of the chat's tools are `NOT_FOR_HALON`.

### The workflows flag

Everything for workspace workflows sits behind `FeatureFlags::WORKFLOWS`, off by default. Without it `Workflow#start_blocked_reason` refuses every start, and `WorkflowRunService` raises `Workflow::Run::Refused` before anything is made, so a trigger, Halon, the dashboard and a sub workflow all stop there. `DefinedWorkflow.runnable?` holds every run already going, so nothing waits out its time, wakes on a signal or carries on until the flag is back ([Held runs](#held-runs)). Pages, Halon tools and MCP tools for workflows check the same flag. Class workflows never look at it. The workflow library page follows it too. The workspace's own skills have a flag of their own, `CUSTOM_SKILLS` (docs/ai.md, A workspace's own skills). A skill a workflow's step names in its config (`skill`) is held back from being deleted or renamed, and a step that runs one the workspace switched off is refused at publish and fails at run time. The canvas's controllers include `WorkflowCanvas`, which includes `RequiresWorkflows` like every workflow page.

### Private inputs

A trigger input marked `private: true`, such as a check's notes, keeps its value apart: encrypted on each version (`workflow_versions.private_inputs`, `Workflow::PrivateInputs`), so a draft that changes it changes nothing live until it is published, and on a run (`workflow_runs.private_inputs`), and never in the trigger, an edit's payload, a run's `inputs`, a step's data or the engine's context. `Workflow::Trigger.sealed` takes the value out wherever a trigger is written (a version's `before_validation`, saved with the version, a draft edit in `Drafting`, saved in the same guarded update as the edit so a refused edit keeps none, and `Workflow#edit!` before the edit is recorded, so a proposal from Halon never sets one). A new draft starts with the values of the version it is opened from, and everywhere else the input reads as its token (`Workflow::Trigger.private_token`). A run is started with the given value or the one its version keeps, and one started again from a step (`WorkflowRunService.rerun_from!`) with the values its first run kept, and `WorkflowHalonStepJob` puts the value back in memory (`Workflow::Run#unsealed`) just before Halon asks the model, whose words are encrypted (`Chat::Message`). Publishing refuses a private input read by any step but Ask Halon and Run a skill, or handed back in the outputs. The library's checks keep their notes this way, and a workflow from the library that keeps its own trigger has an input a newer library version marks private marked private too, on its live version and its draft, with its own value kept (`Workflow::Trigger.with_private_marks`), and `Investigation::Check#to_workflow!` turns a check into a following library workflow on its schedule with its notes kept private.

### Runbooks and their workflow

Where the workspace has workflows a runbook is a guide: its text, its steps as a checklist and its links, for people and Halon. What it runs lives in one workflow it links (`runbooks.workflow_id`, `Runbook::LinkedWorkflow`), and Run it starts that workflow. A runbook links zero or one workflow, since Run it is one button and the runbook's steps, inputs and watch became one workflow. A workflow may be linked by several runbooks, and deleting it leaves each a guide (`on_delete: :nullify`). Without the flag a runbook runs itself exactly as before (docs/ai.md, A saved runbook is run by name).

- **Moving over.** `Runbook#move_runnable_parts!` takes what a runbook runs into a new workflow named after it (its name, or "<name> runbook" when another workflow answers to that name, its other names that are free, its summary as the description) and links it. `Runbook::WorkflowShape` is the one mapping both ways: each step with a tool becomes a `call_tool` step named after its title with the same tool and arguments, in order, the watch a `watch` step after the last of them with the same spec, the inputs with their questions and defaults the manual trigger's inputs, and `{{key}}` becomes `{{inputs.key}}`. The workflow is a version 1 draft written by Firefight (`AUTHOR_FIREFIGHT`), never published and its identity granted nothing, since publishing is an admin's act (Members draft, admins publish). Every step stays on the runbook with its id, title and instruction, its tool and arguments cleared, so an incident it is attached to, its Slack checklist and every action claimed from a step read as before. Conditions, always attach, content, the external link and other names stay on the runbook. `MoveRunbookStepsIntoWorkflows` (migration) moves the runbooks of every workspace that has the flag, and `FeatureFlags.enable!` moves a workspace's when the flag is turned on, so a workspace without workflows is never touched. `test/models/runbook/linked_workflow_test.rb` holds a test per field.
- **Writing one.** With the flag, `Runbook::Upsert` (MCP `upsert_runbook`, the REST API) keeps every step as the checklist and writes the steps that name a tool, the inputs and the watch into the linked workflow (`write_runnable_parts!`), making one when there is none. Each is replaced only when given, and a step list with no tool step changes only the checklist, so reading a runbook and writing it back leaves the workflow alone. A linked workflow changed on its page into something a runbook cannot say (branches, retries, other kinds) is refused rather than written over. An existing workflow's draft takes the new content in one update guarded on its revision, a step keeping its id when it keeps its name. Writing it is `workflows.create`. Over MCP it is then published when the writer may publish it (as `create_workflow` does), else the admins are asked. The API publishes no workflow, so it says the draft waits or asks the admins. The dashboard's runbook form refuses steps that run with the flag on (`RunbooksController::RUNS_IN_ITS_WORKFLOW`) and links a workflow instead.
- **Run it.** `RunbookRunService` starts the linked workflow through `WorkflowRunService` as the workflow's own identity, with the trigger payload naming the runbook and, pressed in an incident, the incident. `Runbook#run_blocked_reason` is the workflow's `run_now_blocked_reason` for the person. On the dashboard (`RunbookRunsController`, `POST /settings/runbooks/:id/runs`, which answers not found without the flag) Run it sits on the runbook's sheet and on each runbook in an incident, asks the run's questions (`RunRunbookDialog`) and toasts with a link to the run. In Slack Run it is on the runbook's message in the incident channel and on its detail view (`Identifiers::RUN_RUNBOOK`, `Interactions::RunRunbookHandler`), which opens `Slack::Modals::RunbookRun`, and the submission (`Interactions::RunbookRunHandler`) starts it and tells the person privately where to follow it. A message posted before a workflow was linked shows Run it once it is next redrawn.
- **Halon and MCP.** `run_runbook` keeps its name and starts the linked workflow, confirmed on the card with the workflow's steps and inputs, and answers with the run's link. `search_runbooks` marks a runbook `runnable` when its workflow can start now and names it, `get_runbook` answers the checklist and the workflow's inputs, watch and steps read back in a runbook's words with its page, and `attach_runbook` and `claim_runbook_step` work on the checklist as before.
- **The editor.** With the flag the runbook form shows a step's title and instruction only, and a Workflow section to link one, open it on its page (`halon/workflows/:id`) and keep the runbook's other names.

## Firefight's library

Firefight ships workflows of its own as data, one file each in `config/workflow_library/<key>.yml`: a name, a description, other names, and a version's `trigger`, `steps`, `edges` and `outputs`. `Workflow::Library` reads them into `Item`s. Each carries a version kept in `config/library_versions.yml` beside a digest of what it says (`FirefightLibrary`, shared with Firefight's skills), so `test/models/firefight_library_test.rb` fails when an item changes without `bin/rails library:versions`.

- **Taking one.** `Workflow.from_library!(item, workspace:, by:, name:, following:, answers:)` makes a workflow whose first version is a draft holding the item as it is, written by Firefight (`Workflow::AUTHOR_FIREFIGHT`), so publishing it is the same step as for any workflow: `WorkflowPublishService`, which grants its own identity what its steps need and schedules it, and its runs go through `WorkflowRunService` like any other. The workflow keeps `library_key`, the `library_version` it holds and what that version said (`library_base`). An item is refused while the workspace cannot run its steps, such as a skill its connections do not offer (`from_library_blocked_reason`, its first publish problem in that workspace, `Item#problems(workspace)`), and a name another workflow already answers to is refused (`name_taken_reason`). A question the item's trigger asks without a default, such as what a scheduled check looks at, needs its answer (`unanswered_library_inputs`), which becomes that question's default in the draft's trigger, so every scheduled run has it. The trigger is the workspace's, so the answer never stops it following.
- **As it is.** `follows_library` workflows move with each new version: `WorkflowLibraryUpgradeJob` (hourly) runs `upgrade_from_library!`, which publishes a new live version with the item's steps, edges and outputs and the workflow's own trigger (the item's when its trigger kind changed), retiring the one that was, and moves an open draft along when its steps are still the old version's, so publishing a schedule change never takes it back. The claim is one update guarded on the `library_version` it held, so two workers move it once. A workflow whose live version or draft has steps that differ from `library_base` is someone's own now (`changed_from_library?`): the upgrade stops it following instead, and from then on it is a copy. So does one whose new version needs more than its identity holds (`needs_more_for?`), since nothing grants without a person: an admin takes it into a draft and publishing grants it. A live version moved on is scheduled again (`schedule!`).
- **A copy.** A workflow made with `following: false`, or one that stopped following, is never changed under the workspace. `library_update` is the item's newer version it has not been told about (newer than `library_version` and `library_dismissed_version`). `Workflow::Changes.between(library_base, item.definition)` says what changed as sentences (steps added, removed or changed by their stable ids, connections, the trigger, the outputs). `take_library!(by:)` opens a draft from the live version with the item's steps and the workflow's trigger, refused while a draft is open ("Publish or discard the open draft first."), and `keep_own!` waits for a newer version.
- **Files.** `Workflow::Document` exports a workflow's live version, or its draft when nothing is live, as `<slug>.workflow.json` (`format`, `format_version`, name, description, other names, and the version's content), and imports one as a new workflow whose first version is a draft written by the person, refused when it is not a workflow, was written by a newer format, holds anything shaped like a credential, or takes a name already taken.
- **The page.** The Library tab of the Workflows page (`WorkflowsController`, `libraryItems` and `libraryWorkflows`, `?tab=library`) lists the workspace's workflows with where each came from, whether it is published, Export, Import, and a copy's newer version with what changed, beside the library's items, each with the questions using it asks (`questions`). `HalonWorkflowLibraryController` answers its actions back to that tab, and its old address `/halon/workflow-library` leads there. `workflows` is a grantable resource: members read, and making a draft from the library or a file is `workflows.create`, taking or keeping a newer version `workflows.update`.
- **The checks Halon runs on a schedule.** Each kind of `Investigation::Check` with a skill has a library item that runs it (`disk_space_check`, `certificate_check`, `error_budget_check`, `cost_check`, and `scheduled_check` for one described only by its notes): a schedule trigger in the runtime's own shape with the check's notes as an input (a default for the four with a skill, none for `scheduled_check`, whose notes are the whole check and which follows the `monitoring` playbook), a `run_skill` step with the notes as its focus, and a for each over its `problems` that raises one notice of the check's signal for each (`raise_notice` from the problem's topic, summary, severity, resource and due date, carrying on past one that cannot be raised), so `Investigation::Notice` says each once and again only when it gets worse. Using `scheduled_check` asks "What should Halon check?", and the answer is kept as that input's value, sealed with the draft's private inputs since the notes are private ([Private inputs](#private-inputs)). A test holds every item runnable in a workspace, and another publishes one and runs it.

## The canvas

A workflow's page is `/halon/workflows/:id` (`WorkflowCanvasController#show`, `pages/halon/workflow.tsx`). The list of workflows is the Workflows page under Halon, which links each row here. The canvas only reads and changes a workflow that exists, and makes no new ones.

### Who may do what

| Action | Ability | Members |
|---|---|---|
| Open the canvas | `workflows.read` | Hold it, as every read of Firefight's own data |
| Change the draft, accept or dismiss Halon's suggestions, undo Halon's change, discard a draft, restore a version, run it by hand, ask an admin to publish | `workflows.create` | Hold it without a grant until an admin takes it away (`WorkspaceMembership::NARROWABLE_KEYS`) |
| Publish, change the workflow's settings, switch it on or off, delete it, answer a request to publish | `workflows.update`, and `permissions.create` when publishing grants anything | Need a grant. Admins and owners hold it |

Every change to the draft lands there and never on the live version, so building is `create` and only what changes a live workflow is `update`. A member's edits are in the workflow's own history as `Workflow::Edit`s. The server reads both from the gateway (`workflowAccess`, `build` and `manage`), since the shared `useCan` answers only for `update`, and the page decides its controls from them, never from a role.

### Asking an admin to publish

The canvas uses the same publish flow as the Workflows page (`WorkflowPublishService`, [The workflow's own identity](#the-workflows-own-identity)). Publish (`WorkflowsController#publish`) sends the draft revision the publisher saw, so a draft changed since is refused, and its dialog lists what the identity is granted. A member's Ask an admin to publish is `ask_publish`, and `myPublishRequest` says whether they asked and why they cannot ask again yet. Someone who may publish sees the waiting requests above the canvas, each with what publishing would grant and Dismiss (`WorkflowPublishRequestsController`, which goes back to the page it was pressed on).

### Step kinds and trigger kinds

The canvas never decides a kind on its own. `Workflow::StepKinds` (`app/models/workflow/step_kinds.rb`) holds one `Kind` per step kind:

| Field | Holds |
|---|---|
| `key` | The step's `kind` |
| `group` | One of `GROUPS`, the Steps table's groups, which the palette lists it under. A kind the app runs names its own (`DefinedWorkflow::Steps::Base::GROUP_*`, which `GROUPS` shares) |
| `label`, `description` | Its name and one line, in the palette and the settings sheet |
| `icon` | One of `ICONS`, drawn by `STEP_ICONS` in `pages/halon/lib/workflow/labels.ts` (a new icon is a type error until it is drawn) |
| `editor` | How its settings are drawn: `fields` (the tool field form over `fields`), or `branch`, `delay`, `for_each`, `run_workflow`, `tool`, `ask_halon` and `watch` for a config a plain form cannot hold |
| `fields` | `ToolField::Field`s for the `fields` editor, or a lambda given the `Facts` for choices that are the workspace's own (Run a skill's skills) |
| `defaults` | The config a new step starts with |
| `outputs` | `->(step, facts)`, the fields it hands on, which the reference picker offers to later steps |
| `routes` | `->(step)`, the routes an edge out of it can carry. `routes_of` adds `error` when the step takes the error route on failure |
| `effect` | `->(step, facts)`, `reads` or `changes`, decided by what it calls and never by its author |
| `reach` | `->(step, facts)`, what the workflow's own identity needs to be granted to run it (`DefinedWorkflow::Reach::Needed`). The node shows Needs grant for what it does not hold yet (`Workflow#grant_needed_for`), which publishing grants |

`Facts` carries the workspace and answers `tool(name)` with what it has (`Chat::Tools::Choices`). The engine's control steps are registered with `register`. Each kind the app runs (`DefinedWorkflow::Steps.kinds`) is registered with `runtime(klass, icon:, editor:, description:, fields:, defaults:, routes:)`, which takes its key, label, group, outputs, effect (`changes?`) and reach from its class, so the canvas and the runtime never disagree on what a step does. A kind is offered only once something runs it (`runnable?`: the engine's `STEP_KINDS` or `DefinedWorkflow.action_kinds`). A new kind the app runs is its class, a line in `DefinedWorkflow::Steps.kinds` and a `runtime` line here, and needs no canvas code unless it needs an editor of its own.

| Kind | Editor |
|---|---|
| `call_tool` | `tool`: the tool from the palette's Tools group or a search, its arguments with the shared tool field form, and How to undo it when the tool changes something |
| `ask_halon` | `ask_halon`: the question, what it judges (usually an earlier value), and up to ten named fields it answers |
| `run_skill` | `fields`: the skill from the workspace's own (`Chat::Skill.available_to`) and the focus |
| `watch` | `watch`: the same editor a runbook's watch afterwards uses (`components/watch/watch-spec-editor.tsx`, `lib/watch-spec.ts`), reading from `watchReads`, the read tools and what is on the map |
| `post_to_channel`, `raise_notice` | `fields`, a message and a summary as paragraph fields (`ToolField::KIND_PARAGRAPH`), the notice's resource picked from the map (`places`) |
| `investigate`, `classify`, `open_incident`, `update_incident`, `post_incident_update`, `page_on_call`, `create_follow_up`, `message_person` | `fields`, with the workspace's severities, types, statuses, roles, runbooks and on-call tools as choices, and fields shown only for the change or person they serve (`shown_when`). A classify's routes are its ways out |
| `status_page_update` | `status_page`: the tool editor, offering only tools marked `statusPage` that change something |


`Workflow::TriggerKinds` does the same for triggers (`label`, `description`, `icon`, `editor`, `fields`, `defaults`, `conditions`, `outputs`, `problems`, `help`), with every kind a published workflow starts from. A kind something happening starts draws its conditions under Only when (`trigger-conditions.tsx`), each a field it offers with the workspace's values picked as badges, and the reference picker offers what its trigger data holds (`outputs`) as `{{trigger.<path>}}`. A list field with a fixed set of values, such as which changes start a trigger, is picked as badges (`choice-list-input.tsx`). `help` is what Halon and MCP agents read about each kind (`Workflow::Authoring.schema`).
 A timed kind's editor is the schedule form the Workflows page's Repeat it uses (`schedule-fields.tsx`, `once-at-fields.tsx`, `lib/schedule.ts`), and a new one starts in the person's own time zone (`startingTrigger`). The keys the editors write into the engine's own steps' config are `Workflow::StepKinds::CONFIG_KEYS`.

### What the page receives

`WorkflowCanvasController::PROPS` names every prop, shared with the page through the generated `WORKFLOW_CANVAS_PROPS`, since each change asks for the ones it can change.

| Prop | Serializer | Holds |
|---|---|---|
| `workflow` | `WorkflowDetailSerializer` | The workflow as its header shows it: name, on or off, state, when it runs and next, the live and draft numbers, what its identity needs and holds, why it cannot run, be published or be deleted, a freeze it would meet, a start that did not happen, and its settings |
| `document` | `WorkflowDocumentSerializer` | The version shown (`Workflow#shown_version`): the one named by `?version=`, else the draft, else the live one, else an empty one not saved yet. Its trigger, every step flattened with the for each it sits in (`Version#placed_steps`, `WorkflowStepNodeSerializer`), every connection (`placed_edges`), its problems, and why it cannot be published or restored |
| `versions` | `WorkflowVersionRowSerializer` | The newest 50 versions, each with its landed edits as sentences (`Workflow::Edit#sentence`) |
| `suggestions` | `WorkflowSuggestionSerializer` | Halon's proposals, each with a step it adds, a connection it adds or takes away, and each changed field's old and new value (`Workflow::Edit#changes_against`) |
| `halonChanges` | `WorkflowHalonChangeSerializer` | Halon's changes that landed on the version shown and on the live version a draft was opened from (`Workflow#halon_changes`), grouped by change set, each with why it cannot be undone |
| `stepKinds`, `triggerKinds` | `WorkflowStepKindSerializer`, `WorkflowTriggerKindSerializer` | The kinds offered |
| `tools` | `WorkflowToolChoiceSerializer` | Deferred. Every tool a Call a tool step can call, with Needs grant |
| `publishRequests` | `WorkflowPublishRequestSerializer` | Requests waiting for an admin |
| `otherWorkflows`, `timeZones` | | What the Run workflow, Delay and schedule editors pick from |
| `teams`, `myPublishRequest`, `workflowAccess` | | The owning teams the settings offer, the person's request to publish, and what they may do |
| `places`, `watchReads` | `RunbookPlaceSerializer`, `RunbookWatchReadSerializer` | Deferred. What is on the map, and what a watch can read of it, which a step's settings pick from (`hooks/use-canvas-choices.ts`) |
| `otherWorkflows`, `timeZones` | | What the Run workflow and Delay editors pick from |
| `runs` | `WorkflowRunRowSerializer` | The newest 50 runs, test runs among them |
| `run` | `WorkflowRunDetailSerializer` | The run `?run=` names, with each step's row (`WorkflowRunStepSerializer`), or null |
| `lastRun` | `WorkflowRunStatesSerializer` | The newest run of the version shown, for Last run |

A step's facts that need the tools list are worked out only when a step calls a tool, since building it reads every connection's schemas.

### Every change is an edit

Each change on the canvas is one `POST /halon/workflows/:id/edits` (`WorkflowEditsController`) with an `operation`, a `payload` and the `base_revision` the person saw, which `Workflow#edit!` applies, and the toast is `Workflow::Edit#notice` ("Check logs was added."). A refusal is the model's sentence as an alert. A change to the live version opens a draft from it, so it names no revision. The settings sheet keeps the revision it was opened on while something is changed in it, so applying names that revision, and a change someone made since to the same step is refused with who made it ("Alice Smith changed this since you looked, so look again before changing it."). While nothing is changed the sheet follows the step as saved. The page reloads its props every five seconds (`usePoll`), so another person's change or a suggestion of Halon's shows without a reload.

- **Moving** is `move_step` with the position React Flow gives on drop, relative to the for each a step sits in.
- **Connecting** drags from a step's way out to another step. A step with routes has one way out per route (`RouteHandles`), named until something is connected to it, after which the connection carries the name. A connection to a step in another for each is refused by the model.
- **A connection is taken away** with its button when selected, or the delete key. A step is removed from its settings, which asks first and names the connections and inner steps that go with it.
- **Adding** a step from the palette drops it where it was let go, inside the innermost for each under the pointer, or, clicked, below the selected step and connected to it unless that step has routes, since which route leads on is the person's to say. The id is made on the page (`newStepId`), which `Workflow::Edit::Operations.prepared` keeps, so the connection can follow at once. The name is the kind's or the tool's, made unique (`newStepName`).
- **Settings** go as one `change_config` with only what changed, a config key that went sent as null so the server drops it. A for each's inner steps and connections are never sent from its settings, since they change by their own edits.
- **Renaming** a step is `rename` on blur or Enter, which rewrites every reference to it. Renaming the workflow is `rename` with no step.
- **The trigger** is `change_trigger` with the whole trigger, from its settings or by picking another kind in the palette.

### Halon's suggestions

A suggestion added to a step is drawn dashed in violet where Halon placed it, one removing a step strikes the step, a connection added is dashed and one taken away struck, and a changed field shows the old value struck beside the new in the settings sheet. Each has Accept and Dismiss, and a banner says how many wait and from which chat or run, with Accept all and Dismiss all (`WorkflowSuggestionsController`, `Workflow#accept_suggestions!` and `dismiss_suggestions!`, which land all of the chosen ones or none). A suggestion already decided is not found.

**Changes by Halon** rings each step, connection and trigger whose last change was Halon's, read across the version and the ones it came from (`Version#last_changes`, over `Version#lineage`), and lists Halon's changes with **Undo**. `Workflow#undo_halon!` makes the version again from where it started without those edits (`Version#content_without`, every other landed edit applied again in order, one that only made sense on top of a left-out edit dropped with it), works out the operations from the version to that (`Workflow::Edit::Diff.operations`) and applies them as the person's edits in one change set with the reason "Undid Halon's change.", all or none. Only Halon's edits that landed on the open draft or the live version can be undone (`undo_blocked_reason`, `undoable_version_ids`). Undoing the live version's change opens a draft, and with a draft open it is undone in the draft: the live version made again without it is where the draft starts, and the draft's own edits are made again on top. The draft is locked from working out the operations until they land, so an edit made meanwhile waits and is checked against the undo. Undo all takes every change the panel lists.

### Versions

The Versions view lists each version with its status, who made it, who published it, and every change on it. Open shows a version on the canvas, read-only (`?version=`), and Restore makes a new draft from it, refused while a draft is open ("Publish or discard the open draft first."). The header publishes the draft (asking first, listing what it grants and what stops it), discards it (asking first), or for a member asks an admin, and beside it runs the live version by hand (the Workflows page's run dialog) and switches it on or off.

### Settings

The Settings view is what the workflow's own identity can do (`ReachCard`) and its settings (`SettingsCard`, `WorkflowsController#update`): its name and description, owning team, AI ceiling per run, runs an hour, one live run per subject, what a change does in a freeze window, and the all clear, and Delete for one that never ran.

### Trying a draft

**Test run** in the header, or **Test this step** in a step's settings, opens a dialog for sample answers to the trigger's inputs and a sample of what started the run, written as JSON or taken from an earlier run, and a switch per step that changes something to make that change for real. `WorkflowTestRunsController` starts it with `WorkflowRunService#start!(test: true)`, on the draft, or the live version when there is no draft, whether or not the workflow is on, as the person testing ([Running safely](#running-safely)):

- **Shown, not made.** Every change a step would make is shown instead (`DefinedWorkflow::Steps::Base#simulated?`, its output marked `simulated`) unless the tester turned that step on (`real_step_keys`).
- **Pins.** A step's output pinned on the draft (`Workflow::Version::Pins`, `workflow_versions.pins`, by step id, with the route for a step that takes one) is copied onto the run as a stand in (`workflow_runs.stand_ins`), and `DefinedWorkflow.stand_in` hands it to the engine, so the step does not run. A pin is taken from a run's step (Pin this output) or written by hand, and rides along to the next draft opened from that version. Pinning is one guarded update on the draft, so a pin never lands on a version published meanwhile. A pin holding a secret is refused.
- **One step.** `up_to` runs the step with only the steps before it (`Version#snapshot_up_to`, a step inside a for each with its for each), each of those standing in with what it gave in the newest run that reached it when it has no pin. Only what runs is checked, so a problem further on does not stop it.
- **What it ran** is kept on the run (`workflow_runs.snapshot`) when it is less than its version or a draft, so the run's view draws what ran even after the draft changes. A sub workflow inside a test run is tried as a test run too.

### A run on the canvas

`?run=` draws a run on the canvas, read-only: each step's state and time on its node (`lib/workflow/run-states.ts`), the way the run went lit, a step inside a for each counting its items. The panel beside it is the run's (`run-summary.tsx`: inputs, what started it, what it handed back, its error, Stop run, Pin) or the picked step's (`run-step-panel.tsx`: what it was given and gave, the results it kept whole opened in a dialog, its gateway calls, its error, and each item for a step inside a for each). The Runs view lists every run, test runs among them, and Last run lays the newest run of the version shown over the editor.

| Action | Endpoint | Rule |
|---|---|---|
| Try again | `POST runs/:run_id/steps/:step_key/retry` | A failed step (`retry_blocked_reason`), the engine's `retry_now!` through `DefinedWorkflow.retry_step!` |
| Skip | `POST runs/:run_id/steps/:step_key/skip` | A failed or waiting step (`skip_blocked_reason`) |
| Start again from here | `POST runs/:run_id/rerun` | A top level step that ended (`rerun_blocked_reason`). `WorkflowRunService.rerun_from!` starts a new run on the same inputs and trigger, every step before it that succeeded standing in with what it gave. A test run starts again as a test run of the draft, a real run as a real run of the live version, so a fix published since is what runs |
| Stop run | `POST runs/:id/cancel` | A run still going (`Workflow::Run#cancel!`), and every run it started |
| Pin, unpin the run | `PATCH runs/:id/pin`, `unpin` | `Workflow::Run#pin!`, which keeps its details past the retention, refused once they went |
| Pin, unpin a step's output | `POST pins`, `DELETE pins/:step_id` | A draft's step |

Each says so in a toast and redirects to the run, and a run going reloads its props every five seconds. Trying, pinning outputs, trying a step again, skipping and starting again are building and running, `workflows.create`, which members hold. Stopping and pinning a run are `workflows.update`, as on the Workflows page.

### Asking Halon beside the canvas

**Ask Halon** in the canvas header opens a chat beside the canvas. It is the person's own chat (`Conversation` of kind personal) with the workflow as its `subject`, started by `WorkflowChatsController` (`POST /halon/workflows/:id/chat`, `investigations.create`, needs Halon on for the workspace) and carried on until they start a new one. `Conversation.beside(workflow, member)` is the newest one they have not archived, and it is listed with their other chats, where it opens in full. `Conversation.asking_blocked_reason` says why someone cannot ask, which the panel shows in place of the composer.

- **Halon is told which workflow is open.** `Conversation::Context#workflow_line` names it in the per turn context, never the prompt template.
- **Two tools, offered wherever workflows are on.** `get_workflow` (`workflows.read`) hands Halon `Workflow#for_halon`: the version the canvas shows, its trigger, steps, edges and outputs, the suggestions still waiting, and every offered step kind with its settings, defaults and outputs (and the tools a Call a tool step may call, once that kind runs). `propose_workflow_edit` (`workflows.create`, building the draft) takes a list of edits, each an operation and its payload as the canvas sends them, and a reason. `Workflow#propose_from_chat!` checks the whole change set against what is there first (`Workflow::Edit::Operations.apply` then `Version.content_problem`), so a change that could never be accepted is refused with the sentence, then proposes the edits as one change set with the chat as `source_chat`. While Halon builds a workflow alone they land in the draft, as any edit of Halon's does. Both take the workflow by id, slug or name, the chat's own by default, so Halon can change a workflow from any chat.
- **The canvas follows the chat.** The panel subscribes to the chat's `ConversationChannel` and reloads the canvas's props when one of Halon's steps finishes, so a suggestion shows as it is made, with the banner naming the chat it came from.

### Phone width

Below 48rem the canvas is a list of the steps in the order they run (`stepsInOrder`), inner steps indented under their for each and where each leads under it, the trigger first and Halon's suggested steps last with Accept and Dismiss. Tapping one opens the same settings in a sheet, and Add a step opens the palette in one. Between 48rem and 64rem the canvas shows with the settings beside it and the palette opens from Add a step.

## Reading runs from the app

Only workflow classes, the engine and the operator console name `SolidWorkflow`. The console lists every run and pauses, resumes, cancels, retries or skips them through `Operator::WorkflowRuns` (`app/models/operator/workflow_runs.rb`). See [operator.md](operator.md).

## Key Engine Files

```
engines/solid_workflow/
  lib/solid_workflow/base.rb              # DSL (step, start!, start_inline!), host hooks
  lib/solid_workflow/interpreter.rb       # Runs a definition, the control steps
  lib/solid_workflow/errors.rb            # Errors, Park and Routed results
  lib/solid_workflow.rb                   # Module config (queue, retries, thresholds), signal!
  app/models/solid_workflow/definition.rb # Reads and checks a definition
  app/models/solid_workflow/condition.rb  # A branch's conditions
  app/models/solid_workflow/workflow.rb   # Workflow AR model + concerns
  app/models/solid_workflow/step.rb       # Step AR model + concerns (Routing, Waitable)
  app/models/solid_workflow/event.rb      # Audit trail events
  app/jobs/solid_workflow/run_step_job.rb # Executes a single step
  app/jobs/solid_workflow/wake_job.rb     # Wakes a parked step at its time
  app/jobs/solid_workflow/step_timeout_job.rb # Ends an attempt past its time limit
  app/jobs/solid_workflow/sweeper_job.rb  # Recovers stuck, orphaned and due steps
  test/                                   # The engine's own tests (bin/rails test engines/solid_workflow/test)
```

App side: `app/models/workflow.rb` and `app/models/workflow/`, `app/workflows/defined_workflow.rb`, `app/services/workflow_run_service.rb`, `config/workflow_library/`.
App side: `app/models/workflow.rb` and `app/models/workflow/`, `app/workflows/defined_workflow.rb`, `app/services/workflow_run_service.rb` and `app/services/workflow_publish_service.rb`. The canvas: `app/controllers/workflow_*_controller.rb` with the `WorkflowCanvas` concern, `app/serializers/workflow_*_serializer.rb`, and `app/frontend/pages/halon/workflow.tsx` with `pages/halon/components/workflow/`, `pages/halon/hooks/` and `pages/halon/lib/workflow/`. Runbooks: `app/models/runbook/linked_workflow.rb`, `app/models/runbook/workflow_shape.rb`, `app/services/runbook_run_service.rb`.
