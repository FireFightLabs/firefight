require "test_helper"

# Trying a draft from the canvas: test runs, pinned outputs, one step at a time, and starting a run again from a step.
class WorkflowTriesTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @workflow = Workflow.create!(workspace: @workspace, name: "Release check")
  end

  def step(id, kind, config = {}) = { "id" => id, "name" => id, "kind" => kind, "config" => config }

  def draft_of(steps, edges = [])
    draft = @workflow.open_draft!(by: @alice)
    draft.update!(steps: steps, edges: edges)
    @workflow.reload
    draft
  end

  def branchy
    draft_of(
      [
        step("decide", "branch", { "routes" => [ { "route" => "yes", "when" => { "left" => "1", "operator" => "equals", "right" => "1" } } ], "otherwise" => "no" }),
        step("yes_path", "delay", { "seconds" => 0 }),
        step("no_path", "delay", { "seconds" => 0 })
      ],
      [ { "from" => "decide", "to" => "yes_path", "route" => "yes" }, { "from" => "decide", "to" => "no_path", "route" => "no" } ]
    )
  end

  def try(**options)
    run = nil
    perform_enqueued_jobs { run = WorkflowRunService.new(@workflow).start!(started_by_kind: Workflow::Run::STARTED_BY_PERSON, started_by: @alice, test: true, **options) }
    run.reload
  end

  def statuses(run) = run.steps.to_h { |row| [ row.step_key, row.status ] }

  test "a test run tries the draft, whether or not anything is live" do
    branchy

    run = try

    assert run.test?
    assert_equal Workflow::Run::STATUS_SUCCEEDED, run.status
    assert_equal({ "decide" => "succeeded", "yes_path" => "succeeded", "no_path" => "bypassed" }, statuses(run))
    assert_equal @workflow.draft, run.version
  end

  test "an output pinned on the draft stands in for its step, its route included, and rides along to the next draft" do
    draft = branchy
    draft.pin!(step_id: "decide", output: { "route" => "no" }, route: "no", by: @alice)

    run = try

    assert_equal({ "decide" => "succeeded", "yes_path" => "bypassed", "no_path" => "succeeded" }, statuses(run))
    assert_equal({ "route" => "no" }, run.steps.find_by!(step_key: "decide").output)
    assert run.stood_in?("decide")

    draft.publish!(by: @alice)
    assert_equal [ "decide" ], @workflow.reload.open_draft!(by: @alice).pins.keys
  end

  test "only a draft's step is pinned, and a pin is named values with no secret in them" do
    draft = branchy

    assert_raises(Workflow::Edit::Refused) { draft.pin!(step_id: "gone", output: {}, by: @alice) }
    assert_raises(Workflow::Edit::Refused) { draft.pin!(step_id: "decide", output: [ 1 ], by: @alice) }
    error = assert_raises(Workflow::Edit::Refused) { draft.pin!(step_id: "decide", output: { "token" => "ghp_#{'a' * 36}" }, by: @alice) }
    assert_match "holds a secret", error.message

    draft.pin!(step_id: "decide", output: { "ok" => true }, by: @alice)
    draft.unpin!("decide")
    assert_empty draft.reload.pins
  end

  test "one step is tried with only the steps before it, taking what they gave in the newest run that reached them" do
    branchy
    try
    @workflow.draft.update!(steps: @workflow.draft.steps.map { |each| each["id"] == "yes_path" ? each.merge("config" => { "seconds" => 0 }) : each })

    run = try(up_to: "yes_path")

    assert_equal %w[decide yes_path], run.ran_snapshot["steps"].map { |each| each["id"] }
    assert run.stood_in?("decide")
    assert_equal({ "decide" => "succeeded", "yes_path" => "succeeded" }, statuses(run))
  end

  test "a test run acts as the tester and makes only the changes they turned on, ones of steps that change something" do
    tell = { "id" => "tell", "name" => "tell", "kind" => "post_to_channel", "config" => { "channel" => "#ops", "message" => "Hello" } }
    @workflow.open_draft!(by: @alice).update!(steps: [ tell, { "id" => "pause", "name" => "pause", "kind" => "delay", "config" => { "seconds" => 0 } } ], edges: [])
    run = try(real_step_keys: [ "pause", "not_a_step" ])

    assert_equal @alice, run.acting_principal
    assert_empty run.real_step_keys
    assert run.steps.find_by!(step_key: "tell").output[DefinedWorkflow::Steps::Base::OUTPUT_SIMULATED]
  end

  test "a run starts again from a step, the steps before it standing in with what they gave" do
    branchy
    first = try

    again = nil
    perform_enqueued_jobs { again = WorkflowRunService.rerun_from!(first, step_key: "yes_path", by: @alice) }
    again.reload

    assert_equal first, again.rerun_of
    assert_equal "yes_path", again.rerun_from_step_key
    assert again.stood_in?("decide")
    assert_not again.stood_in?("yes_path")
    assert_equal({ "decide" => "succeeded", "yes_path" => "succeeded", "no_path" => "bypassed" }, statuses(again))
  end

  test "a step inside a for each is not where a run starts again" do
    branchy
    run = try
    run.steps.create!(step_key: "inner", iteration: "0", status: "succeeded")

    error = assert_raises(Workflow::Run::Refused) { WorkflowRunService.rerun_from!(run, step_key: "inner", by: @alice) }
    assert_equal "That step is not part of the run.", error.message
  end

  test "nothing is tried without anything to try" do
    error = assert_raises(Workflow::Run::Refused) { WorkflowRunService.new(@workflow).start!(started_by_kind: Workflow::Run::STARTED_BY_PERSON, started_by: @alice, test: true) }
    assert_equal "Release check has no steps to test yet.", error.message
  end
end
