# Workflows (SolidWorkflow)

Built on the SolidWorkflow engine (`engines/solid_workflow/`). The engine runs two kinds of workflow:

- **Class workflows**: Firefight's own flows (incident creation, close, update and the rest), a Ruby class per workflow whose steps are methods. They are thin orchestrators that delegate all logic to services.
- **Defined workflows**: kept as data and run by one interpreter class from a snapshot. See [Defined workflows](#defined-workflows).

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

A workflow class may hold its runs back: `runnable?(workflow)` on the class, true for every class workflow. A held run keeps its place. No step is claimed (`RunStepJob`), nothing is enqueued (`enqueue_next_steps`), no parked step is woken at its time (`WakeJob`), and the sweeper skips it. A signal sent to a held run is kept on the step, and once the run may move the sweeper picks it up and carries on.

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
