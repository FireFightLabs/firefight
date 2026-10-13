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
- **Host hooks** (class methods on the subclass): `action_kinds`, `perform(kind, config, workflow:, step:)`, `resolve`, `clean`, `start_sub_workflow`, `runnable?`, `observe(workflow, event)` (told of every event the run records), `result_of`.

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
| `Workflow` | workspace, name, slug, other names (`aliases`, found like a runbook's with `Workflow.named`), description, owner team (a catalog team entry), on or off (`enabled`), `agent` (the machine principal its runs act as, nil until one is made for it), `cost_cap_cents` (nil means no cap), `live_version`, `next_run_at`, `freeze_behaviour`, `runs_per_hour`, `subject_key`, `all_clear`, `library_key`, `origin_conversation` (the chat Halon made it from), `trigger_refusal` |
| `Workflow::PublishRequest` | a member asking the admins to publish a workflow's draft: `requester`, `version`, `requested_at`, `published_at`/`published_by` or `dismissed_at`, the direct messages it sent (`notifications`) |
| `Workflow::Version` | trigger, steps, edges, outputs, `number`, `status` (`draft`, `live`, `retired`, `discarded`), `revision`, author (`author_kind` person or halon, `author`), `reason`, `parent_version`, `published_at`, `published_by` |
| `Workflow::Edit` | one operation (`add_step`, `remove_step`, `move_step`, `connect`, `disconnect`, `change_config`, `change_trigger`, `rename`) with its `payload` and `targets`, author, Halon's `reason` (required for Halon), `base_revision` and `applied_revision`, `status` (`applied`, `proposed`, `accepted`, `dismissed`), `change_set_id`, `source_run`, `source_chat`, `decided_by` |
| `Workflow::Run` | workflow, version, `trigger_kind`, `trigger_payload`, `inputs`, `outputs`, `start_key`, the `agent` it acted as, who started it (`started_by_kind`, `started_by`), `parent_run` and `parent_step_key` for a sub workflow, `status` (`queued`, `running`, `waiting`, `paused`, `succeeded`, `failed`, `cancelled`), `error`, `pinned`, `details_pruned_at`, `test` and `real_step_keys`, `subject_key`, `told_at`, timing |
| `Workflow::Run::Step` | per step and per for each item (`iteration`): status, route, input, output, `saved_result_ids`, `invocation_ids`, attempts, error, timing. Owns the chat a Halon step, a read before a change or a watch keeps |

- **Versions.** One live, at most one draft (partial unique indexes). `Workflow#open_draft!` opens the draft from the live version. `Version#publish!(by:, revision:)` retires the live version and promotes the draft in one transaction, guarded on the revision the publisher saw. A published version never changes. `restore!` makes a new draft from an old version. While a draft is open it is refused with `restore_blocked_reason`, "Publish or discard the open draft first." `problems` is what publishing checks: the trigger, the engine's definition problems, and every reference pointing at an input that exists or a step that runs before it.
- **Edits.** `Workflow#edit!(operation:, payload:, by:, halon:, reason:, base_revision:)`. Each lands with one `update_all` guarded on the draft's revision (`Version::Drafting`). An edit made on an older revision lands on top when nothing it touches changed since, and is refused naming who changed it otherwise. A new step gets its stable id before the edit is recorded. Renaming a step rewrites every `{{steps.old...}}` reference. Renaming the workflow (a rename with no step) changes its name at once.
- **Halon's edits.** Applied directly only while Halon builds a workflow alone (nothing live, no draft a person touched). Otherwise each is a proposal, grouped by `change_set_id`, which `Edit#accept!` applies to the draft and `dismiss!` drops, both guarded so two people deciding at once decide once. `workspaces.halon_applies_workflow_read_fixes` (default off) says whether Halon may apply its own repairs to steps that only read, and nothing reads it yet.
- **Data passing.** `Workflow::Version.filled(value, scope)` fills `{{inputs.x}}`, `{{trigger.x}}`, `{{steps.name.field}}`, `{{item}}` and `{{index}}` through `Placeholders`, the logic `Runbook.filled` uses: a lone reference keeps its type, one naming nothing reads as empty. `Workflow::Run#kept` redacts anything shaped like a credential (`Chat::SecretFree.redacted`) on the way in and out, and keeps an answer over 16 KB whole as a `Chat::SavedResult` owned by the run, leaving its short plain fields and a `saved_result` reference in the step's data.
- **Run records.** `DefinedWorkflow.observe` writes a step's row whenever the engine records an event for it, every step's row on run level events, and the run's status from its engine state (`DefinedWorkflow::RUN_STATUSES`, where a run an operator paused is `paused`, apart from `waiting`). A run's status moves with one guarded update and never leaves a finished state, except a failed run an operator took up again.
- **Who a run acts as.** The workflow's own `agent`, copied onto the run when it starts, whoever started it, apart from a test run (below). See [The workflow's own identity](#the-workflows-own-identity).
- **Retention.** `workspaces.workflow_run_retention_days` (90 by default, 1 to 400) is how long a finished run keeps its details. After it `WorkflowRunRetentionJob` (daily) drops them through `Workflow::Run#prune_details!`: the step rows with their inputs and outputs, the run's saved results, and its inputs, outputs and trigger payload. The run row stays for good as the run's one line, when it ran, its trigger kind, version, status and the agent it acted as, with `details_pruned_at` set. A run that is queued, running, waiting or paused is never pruned, and a pinned run (`pinned`) keeps everything. The claim is one update guarded on the run being finished, unpinned and whole, so a run an operator takes up again or a person pins in between keeps its details, and the engine's later moves never write onto a pruned run. The engine's own rows for a run go after 30 days, as every run's do.

### Step kinds

Each kind a step can be is one class under `app/workflows/defined_workflow/steps/`, listed in `DefinedWorkflow::Steps.kinds`. A kind says its `label` and `group`, whether it `changes?` (decided by what it calls, never by the author), whether a change of it is `undoable?` (and so needs `config.undo`), whether it `checks?` (reads how something stands, so it can follow a change), the `output_fields` later steps may read, its config `problems`, its `reach` (what the workflow's identity needs granted to run it, `DefinedWorkflow::Reach::Needed`) and `describe` for a page. `DefinedWorkflow.perform` runs a kind the app defines, the engine runs `branch` and `delay` itself. Adding a kind is its class and a line in `kinds`.

| Kind | Config | Does |
|---|---|---|
| `call_tool` | `tool`, `arguments`, `undo` | Any tool Halon can call, through the same `Chat::Tools.catalog` entry a chat gets, run on a `Workflow::AgentRun` (the duck type the chat's tools ask of whoever they run for). Output `answer` and `data` (the answer read as JSON). Reads or changes by `DefinedWorkflow::Reach.changes?` (a capability's own `writes`, else `Chat::Tools.kind`, with a read guard shown only what is written out) |
| `ask_halon` | `question`, `data`, `fields` | One structured call (`FirefightAi::WorkflowAnswer`) answering `verdict` (ok, problem, unsure), `summary` and each field. Reads |
| `run_skill` | `skill`, `focus` | `FirefightAi::SkillFollower` follows one skill with only the tools `use_skill` would hand over, on a reads only `Workflow::AgentRun`, and ends with `report_step`: `verdict`, `summary`, `severity`, `findings`. Reads, whatever the skill's tools could do |
| `watch` | the `start_watch` spec | Starts the same `Chat::Watch` a chat keeps (`Conversation::Watches.start` with a `Workflow::WatchHost`), on a chat owned by the step's row, as the run's identity. The watch reports to nobody as it goes, and its end is delivered to the step, which takes the route named for it (`succeeded`, `failed`, `timed_out`, `stopped`) |
| `post_to_channel` | `channel` or `reply_in_chat`, `message` | Firefight's `post_to_channel`, or back where the workflow was made from a chat (`ChannelPostService#reply!`: its thread, or the person's direct messages). Changes, no undo, no freeze or read first |
| `raise_notice` | `signal`, `topic`, `summary`, `severity`, `due_on`, `resource` | `Investigation::Notice.observe!` with the run, said through `Investigation::NoticeDelivery` in the resource's team channel, else the workflow's team, else the monitoring channel. Authorized as `monitoring.create`, never held. Changes, no undo |
| `branch`, `delay` | as above | The engine's own |

- **Work handed off.** A step whose work takes long, Halon or reading how things stand, hands it to a job and parks (`Base#await`): the name is marked asked once in the step's checkpoint with the time (`DefinedWorkflow.mark_asked!`), the job delivers its answer with `DefinedWorkflow.deliver!` (once, by name, in one statement) and wakes the step, which reads it on its next attempt. With nothing delivered within the step's time limit (30 minutes when it sets none) of handing it off, it fails, so work handed off late, such as a read after a long approval, gets its full wait. Each retry of a step asks under its own name (`name#try<n>`, counted from the engine's retry events), never reading what the try before it got back. An error in the Halon job that nobody expected is handed to the step in words. `deliver_for_record!` finds the engine's step from the run's row, for a watch.
- **Refused and failed.** `Base::Refused` is a step's own words for why it cannot go on and is never retried. `Base::Failed` is what it called failing. A step acts once unless its own `retry` says otherwise (`DefinedWorkflow.default_retry_config`). A step's error is stored without the class the engine writes ahead of it (`DefinedWorkflow.error_words`).
- **Every call through the gateway.** `Workflow::AgentRun#tool_call` runs `Chat::ToolCall.run!` as the run's acting principal with source `workflow`, `workflow_run_id` (a column on `ability_invocations` and `ability_approvals`) and `triggered_by_label` naming the run. The step keeps the ledger rows' ids (`workflow_run_steps.invocation_ids`), and the run page lists `run.invocations`.
- **Approvals mid run.** A change an approval rule holds parks the step (`ApprovalResumption.park_workflow_step!`, kind `workflow_step` with the engine step and its key). The decision is delivered to it. Approved, it reads how things stand again (below) and runs exactly that call with the approval. Declined, it fails and takes its error route when it has one. Undecided within its time limit (24 hours by default) the approval expires and the step fails saying so.

### Running safely

- **Test runs.** `WorkflowRunService#start!(test: true, real_step_keys:)` runs the draft, or the live version when there is none, as the person testing (`Workflow::Run#acting_principal`). Reads run for real. A change only shows what it would do (`simulated`), unless its step is among `real_step_keys`. A test run counts against no limit and says nothing when it ends.
- **Freeze windows.** A change inside a window `Workspace::FreezeWindows.covering` finds stops the run with the freeze's sentence, or parks until the window ends when the workflow says `freeze_behaviour` `wait`. `Workflow#freeze_warning` says when the next scheduled time lands in one.
- **Read before a scheduled change.** In a run a Schedule or Once at trigger started (`Workflow::Run#reads_first?`), a change first hands `WorkflowStateCheckJob` the call, which runs `Chat::StateCheck` as the run's identity on a chat owned by the step's row. Anything but unchanged stops it, with `Chat::CurrentState::WORDS`. The same check runs again after an approval.
- **Every change carries its undo and ends with a check.** Publishing (`Workflow::Version#problems`, `Version::Steps`) refuses a step that `undoable?` with no `undo`, and one with no step that `checks?` running after it.
- **Limits.** `runs_per_hour` (60 by default, `rate_blocked_reason`), one live run per subject when `subject_key` names one with a reference to the inputs or the trigger (`subject_for`, a partial unique index on open runs), and, for runs an event starts, `workspaces.workflow_event_runs_per_hour` across the workspace (`Workflow.event_blocked_reason`). Both are counted with the workflow's row locked, and the workspace's for an event, until the run is made, so starts at once cannot each see room for one more. `cost_cap_cents` caps each run's AI: `Workflow::Run#ai_spent_cents` counts every inference of the run and its steps, and a Halon step gets what is left (`Workflow::HalonStep#room_cents`), or nothing and fails when it is spent.

### Triggers

`Workflow::Trigger::Schedule` reads a Schedule or Once at trigger in its own `time_zone`: `repeat` every few `minutes` (5 to 720, counted from the start of the day) or `hours` (at a minute), on `days` of the week `at` a time, or `monthly` on the first to fourth or last weekday. Once at is `at`, a local date and time, at most a year ahead. `next_after` works out the next time, `words` says it. A published workflow starts by hand, on a schedule, once at a time or when another workflow runs it, and any other kind is refused when publishing (`Workflow::Trigger::PUBLISHABLE`).

`Workflow#next_run_at` holds the next time, set when it is published or switched on and cleared when it is switched off (`Workflow::Scheduling#schedule!`). `WorkflowTriggerSweepJob` (every minute) takes each due workflow with `claim_due!`, one statement naming the time it was due, and starts a run with the start key `trigger:<time>`. A start its limits refuse is kept on the workflow (`trigger_refusal`) for its page, and so is one that broke, which never stops the sweep reaching the workflows after it. A one off is done only once a real run ran, never after a test run alone. A one off has no next time once it ran, and is then listed as done.

### The workflow's own identity

An `Agent` made with the workflow (`Workflow#ensure_agent!`, named "<name> workflow", slug `workflow_<slug>`) holds only what was granted to it. It is never listed or managed on the Agents screen, over the API or MCP, and never holds a token (`Agent.standalone`, `ApiKey#not_a_workflows_own`), but it is a principal on the Permissions screen like any agent. `Workflow::Version#reach` reads what its steps need: a connection's read pack for a read through it, the one ability for a change, a system ability for Firefight's own tools, and `map.read` for anything routed through the map. `Workflow#standing` says which it holds.

`WorkflowPublishService#publish!` makes the draft live, grants the identity what it does not hold yet (as the publisher, every environment), and schedules it, in one transaction, then settles every request to publish it. Publishing is `workflows.update`, and granting is `permissions.create`, which the controller and the Slack button authorize. A member holds `workflows.create` without a grant (`WorkspaceMembership::MEMBER_BUILDS`, ledgered unlike participation): they make drafts, test them and run published workflows, and ask the admins to publish (`Workflow::PublishRequest`, once a day per member and workflow like a pack request, a direct message to every admin with Publish, and the Workflows page lists what waits). Publish on a request publishes the draft at the revision the admins were asked about (`PublishRequest#revision`, `stale_reason`) and refuses one changed since, and the publish dialog sends back the revision it showed. The `workflows` ability is hidden from grants without the flag (`Ability::Action.hidden_resources`), on the screens and in what a key's or agent's matrix may hold (`Ability::Grant.replace_system_grants!`). A skill step's reach is only the reads of the tools its skill names, whatever else those tools could do. Without the flag every workflow page answers not found before anything checks who is asking (`RequiresWorkflows` runs first).

### When a run ends

`DefinedWorkflow.observe` enqueues `WorkflowRunEndedJob` when a run reaches a finished state. `WorkflowRunEndService` stops any watch its steps still keep, and, once per run (`claim_telling!`), for a run neither a test nor another workflow's:

- **A failed run** is said in the owning team's notification channel from the catalog, else to whoever published the version by direct message (`post_workflow_failure`). First Halon reads why the failed step failed (`FirefightAi::WorkflowRepair`) and, when its settings caused it, suggests a change as a proposal on the workflow with its reason and the run, which the run's and the workflow's pages show with Accept and Dismiss.
- **An all clear**, for a workflow with `all_clear` on (off by default, including the library's), is one line in the same place when the run succeeded and raised and posted nothing.

### The library

`Workflow::Library` holds the workflows Firefight ships: `check_later` (Once at, reads a resource's status and its key reads against normal, Ask Halon judges, Post to channel or back to the chat) and `probing_scan` (every weekday at 09:00, each connected edge network's security events through a skill with the `security_events` signal, then the `probing_scan` skill, a branch on its verdict and a probing notice). `create!` makes a draft from one, attributed one edit at a time.

### The pages

Under Halon, Workflows (`WorkflowsController`, `/halon/workflows`): the workflows, every run, and the one offs that are done with their runs and Repeat it. A workflow's page shows its steps, what its identity can do, Halon's suggestions, its settings, Run, Test run, Publish or Ask an admin, and its runs. A run's page (`WorkflowRunsController`) shows each step with what it took in and gave back, the calls it made, the notices it raised, Pin (keeps its details past retention) and Stop. Settings, Workspace holds how long runs keep their details (`WorkflowSettingsController`). Every page answers not found without the flag (`RequiresWorkflows`), and the sidebar item shows only with it (`workflowsEnabled`).

### The workflows flag

Everything for workspace workflows sits behind `FeatureFlags::WORKFLOWS`, off by default. Without it `Workflow#start_blocked_reason` refuses every start, and `WorkflowRunService` raises `Workflow::Run::Refused` before anything is made, so a trigger, Halon, the dashboard and a sub workflow all stop there. `DefinedWorkflow.runnable?` holds every run already going, so nothing waits out its time, wakes on a signal or carries on until the flag is back ([Held runs](#held-runs)). Pages, Halon tools and MCP tools for workflows check the same flag. Class workflows never look at it. The workflow library page follows it too. The workspace's own skills follow the same flag, their page, `propose_skill` and loading them alike (docs/ai.md, A workspace's own skills), and a skill a workflow's step names in its config (`skill`) is held back from being deleted or renamed.

## Firefight's library

Firefight ships workflows of its own as data, one file each in `config/workflow_library/<key>.yml`: a name, a description, other names, and a version's `trigger`, `steps`, `edges` and `outputs`. `Workflow::Library` reads them into `Item`s. Each carries a version kept in `config/library_versions.yml` beside a digest of what it says (`FirefightLibrary`, shared with Firefight's skills), so `test/models/firefight_library_test.rb` fails when an item changes without `bin/rails library:versions`.

- **Taking one.** `Workflow.from_library!(item, workspace:, by:, name:, following:)` makes a workflow whose first version is a draft holding the item as it is, written by Firefight (`Workflow::AUTHOR_FIREFIGHT`), so publishing it is the same step as for any workflow. The workflow keeps `library_key`, the `library_version` it holds and what that version said (`library_base`). An item is refused while its steps are ones the runtime does not run (`from_library_blocked_reason`, its first publish problem), and a name another workflow already answers to is refused (`name_taken_reason`).
- **As it is.** `follows_library` workflows move with each new version: `WorkflowLibraryUpgradeJob` (hourly) runs `upgrade_from_library!`, which publishes a new live version with the item's steps, edges and outputs and the workflow's own trigger (the item's when its trigger kind changed), retiring the one that was, and moves an open draft along when its steps are still the old version's, so publishing a schedule change never takes it back. The claim is one update guarded on the `library_version` it held, so two workers move it once. A workflow whose live version or draft has steps that differ from `library_base` is someone's own now (`changed_from_library?`): the upgrade stops it following instead, and from then on it is a copy.
- **A copy.** A workflow made with `following: false`, or one that stopped following, is never changed under the workspace. `library_update` is the item's newer version it has not been told about (newer than `library_version` and `library_dismissed_version`). `Workflow::Changes.between(library_base, item.definition)` says what changed as sentences (steps added, removed or changed by their stable ids, connections, the trigger, the outputs). `take_library!(by:)` opens a draft from the live version with the item's steps and the workflow's trigger, refused while a draft is open ("Publish or discard the open draft first."), and `keep_own!` waits for a newer version.
- **Files.** `Workflow::Document` exports a workflow's live version, or its draft when nothing is live, as `<slug>.workflow.json` (`format`, `format_version`, name, description, other names, and the version's content), and imports one as a new workflow whose first version is a draft written by the person, refused when it is not a workflow, was written by a newer format, holds anything shaped like a credential, or takes a name already taken.
- **The page.** Halon, Workflow library (`HalonWorkflowLibraryController`, `/halon/workflow-library`, `pages/halon/workflow-library.tsx`) lists the workspace's workflows with where each came from, whether it is published, Export, and a copy's newer version with what changed, beside the library's items. `workflows` is a grantable resource: members read, and making a draft from the library or a file is `workflows.create`, taking or keeping a newer version `workflows.update`.
- **The checks Halon runs on a schedule.** Each kind of `Investigation::Check` with a skill has a library item that runs it (`disk_space_check`, `certificate_check`, `error_budget_check`, `cost_check`, and `scheduled_check` for one described only by its notes): a schedule trigger with the check's notes as an input, a step that runs the skill in check mode, a branch on whether it found problems, and a for each that raises a notice for each. Their `run_skill` and `raise_notice` steps are not ones the runtime runs yet, so they are listed and cannot be taken, and a test holds every other part of them well formed.

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
