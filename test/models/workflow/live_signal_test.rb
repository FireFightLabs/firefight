require "test_helper"

class Workflow::LiveSignalTest < ActiveSupport::TestCase
  include ActionCable::TestHelper
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @workflow = Workflow.create!(workspace: @workspace, name: "Release", created_by: @alice)
    @stream = WorkflowChannel.stream_name(@workflow.id)
  end

  test "an edit to the draft tells the open canvas, through the draft's guarded update as well" do
    @workflow.open_draft!(by: @alice)
    pubsub_adapter.clear_messages(@stream)

    @workflow.edit!(operation: Workflow::Edit::OPERATION_ADD_STEP, payload: { "step" => { "id" => "pause", "name" => "pause", "kind" => "delay", "config" => { "seconds" => 0 } } },
                    by: @alice)

    assert_equal [ Workflow::LiveSignal::PART_CANVAS ], parts_sent
  end

  test "nothing is said for a change that rolls back" do
    pubsub_adapter.clear_messages(@stream)
    Workflow.transaction do
      @workflow.update!(description: "Rolled back")
      raise ActiveRecord::Rollback
    end

    assert_no_broadcasts(@stream)
  end

  test "a run starting and moving on tells the open page its runs changed" do
    draft = @workflow.open_draft!(by: @alice)
    draft.update!(trigger: { "kind" => "manual", "inputs" => [] }, steps: [ { "id" => "pause", "name" => "pause", "kind" => "delay", "config" => { "seconds" => 0 } } ])
    pubsub_adapter.clear_messages(@stream)

    perform_enqueued_jobs { WorkflowRunService.new(@workflow).start!(started_by_kind: Workflow::Run::STARTED_BY_PERSON, started_by: @alice, test: true) }

    assert_includes parts_sent, Workflow::LiveSignal::PART_RUNS
  end

  test "a step the engine records tells the open page its runs changed" do
    draft = @workflow.open_draft!(by: @alice)
    draft.update!(trigger: { "kind" => "manual", "inputs" => [] }, steps: [ { "id" => "pause", "name" => "pause", "kind" => "delay", "config" => { "seconds" => 0 } } ])
    run = perform_enqueued_jobs { WorkflowRunService.new(@workflow).start!(started_by_kind: Workflow::Run::STARTED_BY_PERSON, started_by: @alice, test: true) }
    pubsub_adapter.clear_messages(@stream)

    run.reload.record_step!(step_key: "pause", iteration: "", status: DefinedWorkflow::STEP_SUCCEEDED)

    assert_equal [ Workflow::LiveSignal::PART_RUNS ], parts_sent
  end

  test "a schedule time given back by the sweep tells the open canvas" do
    @workflow.update_columns(next_run_at: 1.hour.from_now)
    pubsub_adapter.clear_messages(@stream)

    @workflow.release_due!(5.minutes.ago)

    assert_equal [ Workflow::LiveSignal::PART_CANVAS ], parts_sent
  end

  test "a grant to the workflow's own identity tells its canvas, since Needs grant reads it" do
    agent = @workflow.ensure_agent!
    pubsub_adapter.clear_messages(@stream)

    Ability::Grant.grant!(workspace: @workspace, principal: agent, target: { action: Ability::Action.grantable_for(@workspace).first })

    assert_equal [ Workflow::LiveSignal::PART_CANVAS ], parts_sent
  end

  private

  def parts_sent
    broadcasts(@stream).map { |message| ActiveSupport::JSON.decode(message)["part"] }.uniq
  end
end
