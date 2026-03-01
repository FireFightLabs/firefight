require "test_helper"

class WorkflowEventTest < ActiveSupport::TestCase
  test "creates event for workflow" do
    user = User.create!(name: "Test User", email: "test@example.com")
    workflow = ExampleCalculationWorkflow.start!(user)

    event = workflow.events.first
    assert_equal SolidWorkflow::Events::Workflow::STARTED, event.event_type
    assert_equal workflow.id, event.workflow_id
  end

  test "stores metadata as jsonb" do
    user = User.create!(name: "Test User", email: "test@example.com")
    workflow = ExampleCalculationWorkflow.start!(user)

    workflow.record_event("custom.event", key: "value", number: 123)

    event = workflow.events.where(event_type: "custom.event").first
    assert_equal "custom.event", event.event_type
    assert_equal "value", event.metadata["key"]
    assert_equal 123, event.metadata["number"]
  end

  test "belongs to workflow" do
    user = User.create!(name: "Test User", email: "test@example.com")
    workflow = ExampleCalculationWorkflow.start!(user)
    event = workflow.events.first

    assert_equal workflow, event.workflow
  end
end
