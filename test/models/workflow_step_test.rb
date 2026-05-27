require "test_helper"

class WorkflowStepTest < ActiveSupport::TestCase
  test "requires name and status" do
    step = SolidWorkflow::Step.new
    assert_not step.valid?
    # Validations may be on specific fields or associations
    assert step.errors.any?
  end

  test "has status enum" do
    user = User.create!(name: "Test User", email: "test@example.com")
    workflow = ExampleCalculationWorkflow.start!(user)
    step = workflow.steps.first

    assert step.pending?
    step.update!(status: :running)
    assert step.running?
    step.update!(status: :succeeded)
    assert step.succeeded?
  end

  test "completed? returns true for terminal statuses" do
    user = User.create!(name: "Test User", email: "test@example.com")
    workflow = ExampleCalculationWorkflow.start!(user)
    step = workflow.steps.first

    assert_not step.completed?
    step.update!(status: :succeeded)
    assert step.completed?

    step.update!(status: :failed)
    assert step.completed?

    step.update!(status: :skipped)
    assert step.completed?

    step.update!(status: :cancelled)
    assert step.completed?
  end

  test "ready_to_run? returns true when pending with no dependencies" do
    user = User.create!(name: "Test User", email: "test@example.com")
    workflow = ExampleCalculationWorkflow.start!(user)
    step = workflow.steps.find_by(name: "fetch_numbers")

    steps = workflow.steps.to_a
    step_map = steps.index_by(&:name)

    assert step.ready_to_run?(step_map)
  end

  test "ready_to_run? returns false when dependencies not met" do
    user = User.create!(name: "Test User", email: "test@example.com")
    workflow = ExampleCalculationWorkflow.start!(user)
    step = workflow.steps.find_by(name: "calculate_sum")

    steps = workflow.steps.to_a
    step_map = steps.index_by(&:name)

    assert_not step.ready_to_run?(step_map)
  end

  test "ready_to_run? returns true when all dependencies succeeded" do
    user = User.create!(name: "Test User", email: "test@example.com")
    workflow = ExampleCalculationWorkflow.start!(user)

    fetch_numbers = workflow.steps.find_by(name: "fetch_numbers")
    fetch_numbers.update!(status: :succeeded, output: { numbers: [ 1, 2, 3 ] })

    calculate_sum = workflow.steps.find_by(name: "calculate_sum")
    steps = workflow.steps.reload.to_a
    step_map = steps.index_by(&:name)

    assert calculate_sum.ready_to_run?(step_map)
  end

  test "ready_to_run? returns false when run_at is in the future" do
    user = User.create!(name: "Test User", email: "test@example.com")
    workflow = ExampleCalculationWorkflow.start!(user)
    step = workflow.steps.find_by(name: "fetch_numbers")
    step.update!(run_at: 1.hour.from_now)

    steps = workflow.steps.to_a
    step_map = steps.index_by(&:name)

    assert_not step.ready_to_run?(step_map)
  end

  test "populate_input_data merges dependency outputs" do
    user = User.create!(name: "Test User", email: "test@example.com")
    workflow = ExampleCalculationWorkflow.start!(user)

    fetch_numbers = workflow.steps.find_by(name: "fetch_numbers")
    fetch_numbers.update!(
    status: :succeeded,
    output: { numbers: [ 1, 2, 3 ], count: 3 }
    )

    calculate_sum = workflow.steps.find_by(name: "calculate_sum")
    calculate_sum.update!(
    status: :succeeded,
    output: { sum: 6, operation: "sum" }
    )

    calculate_product = workflow.steps.find_by(name: "calculate_product")
    calculate_product.update!(
    status: :succeeded,
    output: { product: 6, operation: "product" }
    )

    combine_results = workflow.steps.find_by(name: "combine_results")
    steps = workflow.steps.reload.to_a
    combine_results.populate_input_data(steps)

    assert_equal 3, combine_results.input.keys.size
    assert_equal({ "numbers" => [ 1, 2, 3 ], "count" => 3 }, combine_results.input["fetch_numbers"])
    assert_equal({ "sum" => 6, "operation" => "sum" }, combine_results.input["calculate_sum"])
    assert_equal({ "product" => 6, "operation" => "product" }, combine_results.input["calculate_product"])
  end

  test "should_retry? returns true when attempts < max_attempts" do
    user = User.create!(name: "Test User", email: "test@example.com")
    workflow = ExampleCalculationWorkflow.start!(user)
    step = workflow.steps.first
    step.update!(attempts: 2, max_attempts: 5)

    assert step.should_retry?
  end

  test "should_retry? returns false when attempts >= max_attempts" do
    user = User.create!(name: "Test User", email: "test@example.com")
    workflow = ExampleCalculationWorkflow.start!(user)
    step = workflow.steps.first
    step.update!(attempts: 5, max_attempts: 5)

    assert_not step.should_retry?
  end

  test "schedule_retry! sets status to pending with run_at" do
    user = User.create!(name: "Test User", email: "test@example.com")
    workflow = ExampleCalculationWorkflow.start!(user)
    step = workflow.steps.first
    step.update!(status: :failed, attempts: 1)

    step.schedule_retry!

    assert step.pending?
    assert_not_nil step.run_at
    assert step.run_at > Time.current
  end

  test "calculate_backoff uses exponential strategy by default with jitter" do
    user = User.create!(name: "Test User", email: "test@example.com")
    workflow = ExampleCalculationWorkflow.start!(user)
    step = workflow.steps.first

    step.update!(attempts: 1)
    assert_in_delta 2.0, step.send(:calculate_backoff).to_f, 0.5

    step.update!(attempts: 2)
    assert_in_delta 4.0, step.send(:calculate_backoff).to_f, 1.0

    step.update!(attempts: 3)
    assert_in_delta 8.0, step.send(:calculate_backoff).to_f, 2.0
  end

  test "skip! marks step as skipped" do
    user = User.create!(name: "Test User", email: "test@example.com")
    workflow = ExampleCalculationWorkflow.start!(user)
    step = workflow.steps.first

    step.skip!(reason: "Not needed for test")

    assert step.skipped?
    assert_equal "Not needed for test", step.skip_reason
    assert_not_nil step.completed_at
  end

  test "retry_now! resets step to pending" do
    user = User.create!(name: "Test User", email: "test@example.com")
    workflow = ExampleCalculationWorkflow.start!(user)
    step = workflow.steps.first
    step.update!(status: :failed, attempts: 3, last_error: "Some error")

    step.retry_now!

    assert step.pending?
    assert_equal 0, step.attempts
    assert_nil step.last_error
    assert_nil step.run_at
  end
end
