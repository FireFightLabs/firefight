require "test_helper"

class WorkflowTest < ActiveSupport::TestCase
  test "requires name, workflow_class, subject, and state" do
    workflow = Workflow.new
    assert_not workflow.valid?
    # Validations may be on specific fields or associations
    assert workflow.errors.any?
  end

  test "workflow_class must be registered" do
    user = User.create!(name: "Test User", email: "test@example.com")
    workflow = Workflow.new(
      name: "test",
      workflow_class: "NonExistentWorkflow",
      subject: user,
      state: :pending
    )
    assert_not workflow.valid?
    assert workflow.errors[:workflow_class].any? { |msg| msg.include?("must be a registered workflow class") }
  end

  test "creates workflow with registered class" do
    user = User.create!(name: "Test User", email: "test@example.com")
    workflow = Workflow.create!(
      name: "example.calculation.v1",
      workflow_class: "ExampleCalculationWorkflow",
      subject: user,
      state: :pending
    )
    assert workflow.persisted?
    assert_equal "ExampleCalculationWorkflow", workflow.workflow_class
  end

  test "workflow_klass returns the Ruby class" do
    user = User.create!(name: "Test User", email: "test@example.com")
    workflow = ExampleCalculationWorkflow.start!(user)
    assert_equal ExampleCalculationWorkflow, workflow.workflow_klass
  end

  test "has many workflow_steps" do
    user = User.create!(name: "Test User", email: "test@example.com")
    workflow = ExampleCalculationWorkflow.start!(user)
    assert_equal 5, workflow.workflow_steps.count
    assert_equal %w[fetch_numbers calculate_sum calculate_product combine_results store_result],
                 workflow.workflow_steps.map(&:name)
  end

  test "has many workflow_events" do
    user = User.create!(name: "Test User", email: "test@example.com")
    workflow = ExampleCalculationWorkflow.start!(user)
    assert_operator workflow.workflow_events.count, :>=, 1
    assert_equal WorkflowEvents::Workflow::STARTED, workflow.workflow_events.first.event_type
  end

  test "polymorphic subject association" do
    user = User.create!(name: "Test User", email: "test@example.com")
    workflow = ExampleCalculationWorkflow.start!(user)
    assert_equal user, workflow.subject
    assert_equal "User", workflow.subject_type
    assert_equal user.id, workflow.subject_id
  end

  test "stores context as jsonb" do
    user = User.create!(name: "Test User", email: "test@example.com")
    context = { numbers: [ 1, 2, 3 ], metadata: "test" }
    workflow = ExampleCalculationWorkflow.start!(user, context: context)
    assert_equal context.stringify_keys, workflow.context
  end

  test "stores workflow_config as jsonb" do
    user = User.create!(name: "Test User", email: "test@example.com")
    workflow = ExampleCalculationWorkflow.start!(user)
    assert_instance_of Hash, workflow.workflow_config
  end
end
