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
end
