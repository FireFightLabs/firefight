require "test_helper"

class Workflow::RunTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @workflow = Workflow.create!(workspace: @workspace, name: "Check")
    draft = @workflow.open_draft!(by: @alice)
    draft.update!(steps: [ { "id" => "pause", "name" => "pause", "kind" => "delay", "config" => { "seconds" => 1 } } ])
    draft.publish!(by: @alice)
    @run, = Workflow::Run.open!(workflow: @workflow, start_key: "key-1", version: @workflow.reload.live_version, trigger_kind: Workflow::Trigger::KIND_MANUAL,
                                started_by_kind: Workflow::Run::STARTED_BY_PERSON, started_by: @alice)
  end

  test "one start key names one run" do
    again, created = Workflow::Run.open!(workflow: @workflow, start_key: "key-1", version: @workflow.live_version, trigger_kind: Workflow::Trigger::KIND_MANUAL,
                                         started_by_kind: Workflow::Run::STARTED_BY_PERSON)

    assert_equal @run, again
    assert_not created
    assert_equal Workflow::Run::STATUS_QUEUED, @run.status
    assert_equal @workspace, @run.workspace
  end

  test "keeps step data free of anything that looks like a credential" do
    kept = @run.kept({ "said" => "token ghp_#{'a' * 36} here", "nested" => [ { "key" => "AKIAABCDEFGHIJKLMNOP" } ], "count" => 2 })

    assert_match "[REDACTED:", kept["said"]
    assert_no_match(/ghp_a/, kept["said"])
    assert_match "[REDACTED:", kept["nested"].first["key"]
    assert_equal 2, kept["count"]
  end

  test "keeps a large answer whole as a saved result and carries only a summary" do
    kept = @run.kept({ "verdict" => "ok", "log" => "line\n" * 5_000 }, step_name: "check_logs")

    assert_equal "ok", kept["verdict"]
    assert_nil kept["log"]
    saved = @run.saved_results.find(kept.dig("saved_result", "id"))
    assert_equal "result_1", saved.handle
    assert_equal "check_logs", saved.tool_name
    assert_includes saved.content, "\"verdict\": \"ok\""
    assert_nil saved.chat
  end

  test "follows the engine and never leaves a finished one, except a failed run taken up again" do
    @run.record_status!(Workflow::Run::STATUS_QUEUED)
    assert_equal Workflow::Run::STATUS_QUEUED, @run.status

    @run.record_status!(Workflow::Run::STATUS_QUEUED, step_started: true)
    assert_equal Workflow::Run::STATUS_RUNNING, @run.status
    assert @run.started_at

    @run.record_status!(Workflow::Run::STATUS_FAILED, error: "pause failed. password=hunter2hunter2")
    assert_equal Workflow::Run::STATUS_FAILED, @run.status
    assert @run.finished_at

    @run.record_status!(Workflow::Run::STATUS_RUNNING)
    assert_equal Workflow::Run::STATUS_RUNNING, @run.status
    assert_nil @run.finished_at

    @run.record_status!(Workflow::Run::STATUS_SUCCEEDED, outputs: { "ok" => true })
    assert_equal({ "ok" => true }, @run.outputs)
    @run.record_status!(Workflow::Run::STATUS_RUNNING)
    assert_equal Workflow::Run::STATUS_SUCCEEDED, @run.status
  end

  test "writes a step's row whole, one per iteration" do
    @run.record_step!(step_key: "look", iteration: "0", name: "look", kind: "delay", status: "running", attempts: 1)
    @run.record_step!(step_key: "look", iteration: "0", name: "look", kind: "delay", status: "failed", attempts: 1, error: "RuntimeError: broke\nbacktrace")
    @run.record_step!(step_key: "look", iteration: "1", name: "look", kind: "delay", status: "succeeded", attempts: 1)

    assert_equal 2, @run.steps.count
    failed = @run.steps.find_by!(iteration: "0")
    assert_equal "failed", failed.status
    assert_equal "RuntimeError: broke", failed.error
  end

  test "a paused run reads as paused, apart from waiting, and carries on when resumed" do
    @run.record_status!(Workflow::Run::STATUS_RUNNING)
    @run.record_status!(DefinedWorkflow::RUN_STATUSES.fetch("paused"))
    assert_equal Workflow::Run::STATUS_PAUSED, @run.status
    assert_not @run.finished?

    @run.record_status!(DefinedWorkflow::RUN_STATUSES.fetch("waiting"))
    assert_equal Workflow::Run::STATUS_WAITING, @run.status
  end

  test "drops a run's details past the workspace's retention and keeps its one line" do
    @workspace.update!(workflow_run_retention_days: 30)
    @run.update!(status: Workflow::Run::STATUS_SUCCEEDED, finished_at: 31.days.ago, inputs: { "region" => "eu" }, outputs: { "ok" => true },
                 trigger_payload: { "by" => "hand" }, private_inputs: { "notes" => "Leave the replica alone." }.to_json, agent: nil)
    @run.record_step!(step_key: "pause", iteration: "", name: "pause", kind: "delay", status: "succeeded", attempts: 1, input: { "seconds" => 1 })
    @run.saved_results.keep!(tool_name: "pause", text: "kept whole")

    recent, = open_run("recent", status: Workflow::Run::STATUS_SUCCEEDED, finished_at: 2.days.ago)
    pinned, = open_run("pinned", status: Workflow::Run::STATUS_FAILED, finished_at: 60.days.ago, pinned: true)
    going, = open_run("going", status: Workflow::Run::STATUS_PAUSED)

    assert_equal 1, Workflow::Run.prune_details!(@workspace)

    @run.reload
    assert @run.details_pruned?
    assert_empty @run.steps
    assert_empty @run.saved_results
    assert_equal({}, @run.inputs)
    assert_nil @run.outputs
    assert_equal({}, @run.private_input_values)
    assert_equal Workflow::Run::STATUS_SUCCEEDED, @run.status
    assert_equal @workflow.live_version, @run.version
    assert_equal Workflow::Trigger::KIND_MANUAL, @run.trigger_kind
    [ recent, pinned, going ].each { |kept| assert_not kept.reload.details_pruned? }
  end

  test "a run pinned or taken up again before it is pruned keeps its details" do
    @run.update!(status: Workflow::Run::STATUS_FAILED, finished_at: 200.days.ago)
    stale = Workflow::Run.find(@run.id)
    Workflow::Run.where(id: @run.id).update_all(pinned: true)

    assert_not stale.prune_details!
    assert_not @run.reload.details_pruned?
  end

  test "a pruned run is left as its one line when the engine moves again" do
    @run.update!(status: Workflow::Run::STATUS_FAILED, finished_at: 200.days.ago)
    @run.prune_details!

    @run.record_status!(Workflow::Run::STATUS_RUNNING)
    @run.record_step!(step_key: "pause", iteration: "", name: "pause", kind: "delay", status: "running", attempts: 2)

    assert_equal Workflow::Run::STATUS_FAILED, @run.reload.status
    assert_empty @run.steps
  end

  test "a workspace keeps run details 90 days unless it chose between 1 and 400" do
    assert_equal 90, Workspace.new.workflow_run_retention_days
    assert_not @workspace.update(workflow_run_retention_days: 0)
    assert_not @workspace.update(workflow_run_retention_days: 401)
    assert @workspace.update(workflow_run_retention_days: 400)
  end

  private

  def open_run(key, **attributes)
    Workflow::Run.open!(workflow: @workflow, start_key: key, version: @workflow.live_version, trigger_kind: Workflow::Trigger::KIND_MANUAL,
                        started_by_kind: Workflow::Run::STARTED_BY_PERSON, **attributes)
  end
end
