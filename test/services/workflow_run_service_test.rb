require "test_helper"

class WorkflowRunServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    FeatureFlags.enable!(@workspace, FeatureFlags::WORKFLOWS)
  end

  def step(id, kind, config = {}, **extra) = { "id" => id, "name" => id, "kind" => kind, "config" => config }.merge(extra.stringify_keys)

  def edge(from, to, route = nil) = { "from" => from, "to" => to, "route" => route }.compact

  def published(name, steps:, edges: [], trigger: { "kind" => "manual", "inputs" => [] }, outputs: {})
    workflow = Workflow.create!(workspace: @workspace, name: name, created_by: @alice)
    draft = workflow.open_draft!(by: @alice)
    draft.update!(trigger: trigger, steps: steps, edges: edges, outputs: outputs)
    draft.publish!(by: @alice)
    workflow.reload
  end

  def refusal(workflow) = assert_raises(Workflow::Run::Refused) { WorkflowRunService.new(workflow).start!(started_by_kind: Workflow::Run::STARTED_BY_PERSON, started_by: @alice) }.message

  def start(workflow, **options)
    run = nil
    perform_enqueued_jobs { run = WorkflowRunService.new(workflow).start!(started_by_kind: Workflow::Run::STARTED_BY_PERSON, started_by: @alice, **options) }
    run.reload
  end

  test "refuses to start anything for a workspace without the workflows flag" do
    workflow = published("Check", steps: [ step("pause", "delay", { "seconds" => 1 }) ])
    FeatureFlags.disable!(@workspace, FeatureFlags::WORKFLOWS)

    assert_equal "Workflows are not switched on for this workspace.", refusal(workflow)
    assert_empty workflow.runs
  end

  test "refuses a switched off workflow, one never published, and missing inputs" do
    off = published("Off", steps: [ step("pause", "delay", { "seconds" => 1 }) ])
    off.update!(enabled: false)
    assert_equal "Off is switched off.", refusal(off)

    unpublished = Workflow.create!(workspace: @workspace, name: "Unpublished")
    assert_equal "Unpublished has no published version to run.", refusal(unpublished)

    asks = published("Asks", trigger: { "kind" => "manual", "inputs" => [ { "key" => "region", "question" => "Which region?" } ] },
                             steps: [ step("pause", "delay", { "seconds" => "{{inputs.region}}" }) ])
    assert_equal "Asks needs a value for region.", refusal(asks)
  end

  test "a run follows the engine, records every step by its stable id, and outlives the engine's cleanup" do
    workflow = published(
      "Release check",
      trigger: { "kind" => "manual", "inputs" => [ { "key" => "service", "question" => "Which service?", "default" => "web" } ] },
      steps: [
        step("decide", "branch", { "routes" => [ { "route" => "web", "when" => { "left" => "{{inputs.service}}", "operator" => "equals", "right" => "web" } } ],
                                   "otherwise" => "other" }),
        step("wait_a_bit", "delay", { "minutes" => 10 }),
        step("other_path", "delay", { "seconds" => 1 })
      ],
      edges: [ edge("decide", "wait_a_bit", "web"), edge("decide", "other_path", "other") ],
      outputs: { "service" => "{{inputs.service}}" }
    )

    run = start(workflow)

    assert_equal Workflow::Run::STATUS_WAITING, run.status
    assert_equal({ "service" => "web" }, run.inputs)
    assert_equal workflow.live_version, run.version
    assert_equal @alice, run.started_by
    assert_equal %w[succeeded waiting bypassed], %w[decide wait_a_bit other_path].map { |key| run.steps.find_by!(step_key: key).status }
    assert_equal "web", run.steps.find_by!(step_key: "decide").route

    travel 11.minutes do
      perform_enqueued_jobs { SolidWorkflow::SweeperJob.perform_now }
    end

    run.reload
    assert_equal Workflow::Run::STATUS_SUCCEEDED, run.status
    assert_equal({ "service" => "web" }, run.outputs)
    assert run.finished_at
    assert_equal "succeeded", run.steps.find_by!(step_key: "wait_a_bit").status

    travel 40.days do
      SolidWorkflow::CleanupJob.perform_now
    end
    assert_nil SolidWorkflow::Workflow.find_by(start_key: DefinedWorkflow.start_key_for(run))
    assert_equal 3, run.reload.steps.count
    assert_equal Workflow::Run::STATUS_SUCCEEDED, run.status
  end

  test "editing the draft after a run started changes nothing in that run" do
    workflow = published("Snapshot", steps: [ step("pause", "delay", { "minutes" => 5 }), step("look", "wait_for_event", { "event" => "go" }, timeout_seconds: 600) ],
                                     edges: [ edge("pause", "look") ])
    run = start(workflow)

    draft = workflow.open_draft!(by: @alice)
    workflow.edit!(operation: Workflow::Edit::OPERATION_REMOVE_STEP, payload: { "step_id" => "look" }, by: @alice, base_revision: draft.revision)
    draft.reload.publish!(by: @alice)

    travel 6.minutes do
      perform_enqueued_jobs { SolidWorkflow::SweeperJob.perform_now }
    end
    assert_equal "waiting", run.reload.steps.find_by!(step_key: "look").status
  end

  test "one start key gives one run" do
    workflow = published("Once", steps: [ step("pause", "delay", { "minutes" => 5 }) ])

    first = start(workflow, start_key: "schedule:2026-10-13T09:00")
    again = start(workflow, start_key: "schedule:2026-10-13T09:00")

    assert_equal first, again
    assert_equal 1, workflow.runs.count
  end

  test "once at waits for its time before any step runs" do
    workflow = published("Later", steps: [ step("pause", "delay", { "seconds" => 1 }) ])

    run = start(workflow, not_before: 30.minutes.from_now, trigger_kind: Workflow::Trigger::KIND_ONCE_AT)

    assert_equal Workflow::Run::STATUS_WAITING, run.status
    assert_equal "waiting", run.steps.find_by!(step_key: "pause").status
  end

  test "a run workflow step starts the named workflow as a child run and takes its outputs" do
    published("Doubler", trigger: { "kind" => "called", "inputs" => [ { "key" => "n", "question" => "Which number?" } ] },
                         steps: [ step("hold", "delay", { "seconds" => 0 }) ], outputs: { "answer" => "{{inputs.n}}" })
    parent = published("Caller", steps: [ step("call", "run_workflow", { "workflow" => "doubler", "inputs" => { "n" => 21 } }), step("after", "delay", { "seconds" => 0 }) ],
                                 edges: [ edge("call", "after") ])

    run = start(parent)

    assert_equal Workflow::Run::STATUS_SUCCEEDED, run.status, run.error
    child = run.child_runs.sole
    assert_equal "Doubler", child.workflow.name
    assert_equal Workflow::Run::STARTED_BY_WORKFLOW, child.started_by_kind
    assert_equal Workflow::Trigger::KIND_CALLED, child.trigger_kind
    assert_equal "call", child.parent_step_key
    assert_equal({ "answer" => 21 }, run.steps.find_by!(step_key: "call").output)
  end

  test "a for each records one row per item" do
    workflow = published("Each", steps: [ step("each", "for_each", { "items" => %w[web api], "steps" => [ step("look", "delay", { "seconds" => 0 }) ], "edges" => [] }) ])

    run = start(workflow)

    assert_equal Workflow::Run::STATUS_SUCCEEDED, run.status
    assert_equal [ "0", "1" ], run.steps.where(step_key: "look").order(:iteration).pluck(:iteration)
    assert_equal 2, run.steps.find_by!(step_key: "each").output["count"]
  end

  test "a signal reaches a waiting run, and its payload is redacted on the way in" do
    workflow = published("Waits", steps: [ step("reply", "wait_for_event", { "event" => "reply" }, timeout_seconds: 600) ])
    run = start(workflow)

    perform_enqueued_jobs { SolidWorkflow.signal!("reply", { "token" => "ghp_#{'a' * 36}" }) }

    run.reload
    assert_equal Workflow::Run::STATUS_SUCCEEDED, run.status
    assert_match "[REDACTED", run.steps.find_by!(step_key: "reply").output.dig("event", "token")
  end

  test "a run held when the flag is turned off carries on once it is back" do
    workflow = published("Held", steps: [ step("pause", "delay", { "minutes" => 5 }) ])
    run = start(workflow)
    FeatureFlags.disable!(@workspace, FeatureFlags::WORKFLOWS)

    travel 6.minutes do
      perform_enqueued_jobs { SolidWorkflow::SweeperJob.perform_now }
      assert_equal Workflow::Run::STATUS_WAITING, run.reload.status

      FeatureFlags.enable!(@workspace, FeatureFlags::WORKFLOWS)
      perform_enqueued_jobs { SolidWorkflow::SweeperJob.perform_now }
    end
    assert_equal Workflow::Run::STATUS_SUCCEEDED, run.reload.status
  end

  test "class workflows run whatever the flag says" do
    FeatureFlags.disable!(@workspace, FeatureFlags::WORKFLOWS)
    user = User.create!(name: "Flag Off", email: "flag-off-#{SecureRandom.hex(3)}@example.com")

    assert ExampleCalculationWorkflow.start_inline!(user, context: { numbers: [ 1, 2 ] }).succeeded?
  end
end
