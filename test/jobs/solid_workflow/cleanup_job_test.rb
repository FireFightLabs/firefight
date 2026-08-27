require "test_helper"

class SolidWorkflow::CleanupJobTest < ActiveJob::TestCase
  setup do
    @user = User.create!(name: "Cleanup User", email: "cleanup-#{SecureRandom.hex(4)}@example.com")
  end

  test "deletes completed workflows older than retention cutoff" do
    old = SolidWorkflow::Workflow.create!(
      name: "x.v1", workflow_class: "ExampleCalculationWorkflow",
      subject: @user, state: :succeeded, completed_at: 31.days.ago
    )
    recent = SolidWorkflow::Workflow.create!(
      name: "x.v1", workflow_class: "ExampleCalculationWorkflow",
      subject: @user, state: :succeeded, completed_at: 1.day.ago
    )
    active = SolidWorkflow::Workflow.create!(
      name: "x.v1", workflow_class: "ExampleCalculationWorkflow",
      subject: @user, state: :running, completed_at: nil, updated_at: 60.days.ago
    )

    SolidWorkflow::CleanupJob.new.perform

    assert_not SolidWorkflow::Workflow.exists?(old.id)
    assert SolidWorkflow::Workflow.exists?(recent.id)
    assert SolidWorkflow::Workflow.exists?(active.id)
  end

  test "respects retention kwarg" do
    workflow = SolidWorkflow::Workflow.create!(
      name: "x.v1", workflow_class: "ExampleCalculationWorkflow",
      subject: @user, state: :succeeded, completed_at: 8.days.ago
    )

    SolidWorkflow::CleanupJob.new.perform(retention: 7.days)
    assert_not SolidWorkflow::Workflow.exists?(workflow.id)
  end

  test "cascades delete through child steps and events" do
    workflow = ExampleCalculationWorkflow.start_inline!(@user, context: { numbers: [ 1, 2, 3 ] })
    workflow.update!(state: :succeeded, completed_at: 31.days.ago)

    step_ids = workflow.steps.pluck(:id)
    event_ids = workflow.events.pluck(:id)
    assert step_ids.any?, "fixture should have steps"
    assert event_ids.any?, "fixture should have events"

    SolidWorkflow::CleanupJob.new.perform

    assert_not SolidWorkflow::Workflow.exists?(workflow.id)
    assert_equal 0, SolidWorkflow::Step.where(id: step_ids).count
    assert_equal 0, SolidWorkflow::Event.where(id: event_ids).count
  end
end
