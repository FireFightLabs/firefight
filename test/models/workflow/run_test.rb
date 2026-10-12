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
end
