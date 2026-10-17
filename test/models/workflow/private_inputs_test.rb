require "test_helper"

class Workflow::PrivateInputsTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  NOTES = "Leave the billing replica alone, it is resized on Fridays.".freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    FirefightAi::WorkflowRepair.any_instance.stubs(:suggest).returns(nil)
  end

  def trigger(default: NOTES)
    { "kind" => "manual", "inputs" => [ { "key" => "notes", "question" => "What should Halon look at?", "default" => default, "private" => true } ] }
  end

  def skill_step(focus = "{{inputs.notes}}")
    { "id" => "step_check", "name" => "check", "kind" => "run_skill", "config" => { "skill" => "probing_scan", "focus" => focus } }
  end

  def workflow!(steps: [ skill_step ], name: "Probe")
    workflow = Workflow.create!(workspace: @workspace, name: name, created_by: @alice)
    workflow.open_draft!(by: @alice).update!(trigger: trigger, steps: steps)
    workflow.reload
  end

  def stored_trigger(version) = Workflow::Version.connection.select_value("SELECT trigger::text FROM workflow_versions WHERE id = #{Workflow::Version.connection.quote(version.id)}")

  test "a private input's value is kept apart from the trigger, encrypted on its version" do
    workflow = workflow!

    assert_equal NOTES, workflow.draft.private_input_values["notes"]
    assert_not_includes stored_trigger(workflow.draft), "billing replica"
    raw = Workflow.connection.select_value("SELECT private_inputs FROM workflow_versions WHERE id = #{Workflow.connection.quote(workflow.draft.id)}")
    assert_not_includes raw, "billing replica"
    assert Workflow::Trigger.private?(workflow.draft.trigger, "notes")
  end

  test "a person changing the trigger keeps the value private, and the edit keeps no copy of it" do
    workflow = workflow!
    edit = workflow.edit!(operation: Workflow::Edit::OPERATION_CHANGE_TRIGGER, by: @alice, payload: { "trigger" => trigger(default: "Look only at shop.") })

    assert_equal "Look only at shop.", workflow.reload.draft.private_input_values["notes"]
    assert_not_includes Workflow.connection.select_value("SELECT private_inputs FROM workflow_versions WHERE id = #{Workflow.connection.quote(workflow.draft.id)}"), "Look only at shop"
    assert_not_includes edit.reload.payload.to_json, "Look only at shop"
    assert_not_includes stored_trigger(workflow.draft), "Look only at shop"
  end

  test "a run keeps the value encrypted and hands it only to the Halon step, in memory" do
    workflow = workflow!
    WorkflowPublishService.new(workflow).publish!(workflow.draft, by: @alice)
    Workflow::HalonStep.any_instance.expects(:follow!).with(skill_name: "probing_scan", focus: NOTES).returns({ "verdict" => "ok", "summary" => "Fine." })

    run = nil
    perform_enqueued_jobs { run = WorkflowRunService.new(workflow.reload).start!(started_by_kind: Workflow::Run::STARTED_BY_PERSON, started_by: @alice) }

    assert_equal Workflow::Run::STATUS_SUCCEEDED, run.reload.status, run.error
    assert_equal NOTES, run.private_input_values["notes"]
    assert_equal Workflow::Trigger.private_token("notes"), run.inputs["notes"]
    assert_not_includes run.steps.sole.input.to_json, "billing replica"
    assert_not_includes SolidWorkflow::Workflow.find_by!(start_key: DefinedWorkflow.start_key_for(run)).context.to_json, "billing replica"
  end

  test "a value given for a run stands in for the kept one, encrypted the same way" do
    workflow = workflow!
    WorkflowPublishService.new(workflow).publish!(workflow.draft, by: @alice)
    Workflow::HalonStep.any_instance.expects(:follow!).with(skill_name: "probing_scan", focus: "Only shop.").returns({ "verdict" => "ok", "summary" => "Fine." })

    run = nil
    perform_enqueued_jobs do
      run = WorkflowRunService.new(workflow.reload).start!(started_by_kind: Workflow::Run::STARTED_BY_PERSON, started_by: @alice, inputs: { "notes" => "Only shop." })
    end

    assert_equal "Only shop.", run.reload.private_input_values["notes"]
  end

  test "a run started again from a step keeps the private value its first run was started with" do
    workflow = workflow!
    WorkflowPublishService.new(workflow).publish!(workflow.draft, by: @alice)
    Workflow::HalonStep.any_instance.stubs(:follow!).returns({ "verdict" => "ok", "summary" => "Fine." })
    first = nil
    perform_enqueued_jobs do
      first = WorkflowRunService.new(workflow.reload).start!(started_by_kind: Workflow::Run::STARTED_BY_PERSON, started_by: @alice, inputs: { "notes" => "Only shop." })
    end

    again = nil
    perform_enqueued_jobs { again = WorkflowRunService.rerun_from!(first.reload, step_key: "step_check", by: @alice) }

    assert_equal "Only shop.", again.reload.private_input_values["notes"]
    assert_equal Workflow::Trigger.private_token("notes"), again.inputs["notes"]
  end

  test "a draft's new private value waits for publishing, and runs of the live version keep the published one" do
    workflow = workflow!
    WorkflowPublishService.new(workflow).publish!(workflow.draft, by: @alice)
    workflow.reload.edit!(operation: Workflow::Edit::OPERATION_CHANGE_TRIGGER, by: @alice, payload: { "trigger" => trigger(default: "Only shop.") })
    Workflow::HalonStep.any_instance.expects(:follow!).with(skill_name: "probing_scan", focus: NOTES).returns({ "verdict" => "ok", "summary" => "Fine." })

    run = nil
    perform_enqueued_jobs { run = WorkflowRunService.new(workflow.reload).start!(started_by_kind: Workflow::Run::STARTED_BY_PERSON, started_by: @alice) }

    assert_equal NOTES, run.reload.private_input_values["notes"]
    assert_equal "Only shop.", workflow.draft.private_input_values["notes"]
    WorkflowPublishService.new(workflow).publish!(workflow.draft, by: @alice)
    assert_equal "Only shop.", workflow.reload.live_version.private_input_values["notes"]
  end

  test "an edit refused for a change made since keeps no private value" do
    workflow = workflow!
    seen = workflow.draft.revision
    workflow.edit!(operation: Workflow::Edit::OPERATION_CHANGE_TRIGGER, by: @alice, payload: { "trigger" => trigger(default: "Only shop.") }, base_revision: seen)

    assert_raises(Workflow::Edit::Refused) do
      workflow.edit!(operation: Workflow::Edit::OPERATION_CHANGE_TRIGGER, by: workspace_memberships(:bob_workspace_one),
                     payload: { "trigger" => trigger(default: "Only billing.") }, base_revision: seen)
    end

    assert_equal "Only shop.", workflow.reload.draft.private_input_values["notes"]
  end

  test "a version that is not saved keeps no private value anywhere" do
    workflow = workflow!
    refused = workflow.versions.new(number: workflow.draft.number, status: Workflow::Version::STATUS_DRAFT, author_kind: Workflow::AUTHOR_PERSON,
                                    trigger: trigger(default: "Only billing."), steps: [ skill_step ])

    assert_not refused.save
    assert_equal NOTES, workflow.reload.draft.private_input_values["notes"]
  end

  test "a saved value stands in only for an input still marked private" do
    plain = { "kind" => "manual", "inputs" => [ { "key" => "notes", "question" => "What should Halon look at?" } ] }

    resolved = Workflow::Trigger.resolve_inputs(plain, {}, private_values: { "notes" => NOTES })

    assert_empty resolved.values
    assert_equal [ "notes" ], resolved.missing.map { |input| input["key"] }
    assert_equal NOTES, Workflow::Trigger.resolve_inputs(trigger(default: nil), {}, private_values: { "notes" => NOTES }).values["notes"]
  end

  test "a trigger edit that takes the private mark off drops the kept value, so a run never reads it as a plain input" do
    workflow = workflow!
    plain = { "kind" => "manual", "inputs" => [ { "key" => "notes", "question" => "What should Halon look at?" } ] }
    workflow.edit!(operation: Workflow::Edit::OPERATION_CHANGE_TRIGGER, by: @alice, payload: { "trigger" => plain })

    assert_empty workflow.reload.draft.private_input_values
    assert_nil Workflow.connection.select_value("SELECT private_inputs FROM workflow_versions WHERE id = #{Workflow.connection.quote(workflow.draft.id)}")
  end

  test "a version saved with a trigger that no longer marks an input private keeps no value for it" do
    workflow = workflow!
    workflow.draft.update!(trigger: { "kind" => "manual", "inputs" => [ { "key" => "notes", "question" => "What should Halon look at?" } ] })

    assert_empty workflow.reload.draft.private_input_values
  end

  test "only a Halon step may read a private input" do
    post = { "id" => "step_post", "name" => "post", "kind" => "post_to_channel", "config" => { "channel" => "#ops", "message" => "{{inputs.notes}}" } }
    workflow = workflow!(steps: [ post ])

    assert_includes workflow.draft.problems, "post uses {{inputs.notes}}, which is private, so only a Halon step may read it."
    assert_not workflow!(steps: [ skill_step ], name: "Probe again").draft.problems.any? { |problem| problem.include?("private") }
  end

  test "a check becomes a library workflow on its schedule, with its notes kept private" do
    check = @workspace.investigation_checks.create!(name: "Disks every Monday", kind: Investigation::Check::KIND_DISK, cadence: Investigation::Check::CADENCE_WEEKLY,
                                                     weekday: 1, hour: 7, time_zone: "Europe/Berlin", notes: NOTES, created_by: @alice)

    workflow = check.to_workflow!(by: @alice)

    assert_equal [ "Disks every Monday", "disk_space_check", true ], workflow.values_at(:name, :library_key, :follows_library)
    assert_equal NOTES, workflow.draft.private_input_values["notes"]
    trigger = workflow.draft.trigger
    assert_equal [ "days", [ 1 ], "07:00", "Europe/Berlin" ], trigger.values_at("repeat", "days", "at", "time_zone")
    assert_not_includes stored_trigger(workflow.draft), "billing replica"
    assert workflow.following_library?, "a new schedule keeps it following the library"
  end
end
