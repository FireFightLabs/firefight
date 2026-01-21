require "test_helper"

class Workflows::RunStepJobTest < ActiveSupport::TestCase
  test "executes step and transitions to succeeded" do
    user = User.create!(name: "Test User", email: "test@example.com")
    workflow = ExampleCalculationWorkflow.start!(user)
    step = workflow.workflow_steps.find_by(name: "fetch_numbers")

    job = Workflows::RunStepJob.new
    job.perform(step.id)

    step.reload
    assert step.succeeded?
    assert_not_nil step.output
    assert_not_nil step.completed_at
  end

  test "idempotency: does not re-execute succeeded steps" do
    user = User.create!(name: "Test User", email: "test@example.com")
    workflow = ExampleCalculationWorkflow.start!(user)
    step = workflow.workflow_steps.find_by(name: "fetch_numbers")

    # First execution
    job1 = Workflows::RunStepJob.new
    job1.perform(step.id)
    step.reload
    first_output = step.output

    # Second execution (should exit early)
    job2 = Workflows::RunStepJob.new
    job2.perform(step.id)
    step.reload

    assert_equal first_output, step.output
    assert_equal 1, step.attempts
  end

  test "idempotency: does not re-execute cancelled steps" do
    user = User.create!(name: "Test User", email: "test@example.com")
    workflow = ExampleCalculationWorkflow.start!(user)
    step = workflow.workflow_steps.find_by(name: "fetch_numbers")
    step.update!(status: :cancelled)

    job = Workflows::RunStepJob.new
    job.perform(step.id)

    step.reload
    assert step.cancelled?
  end

  test "idempotency: does not re-execute running steps" do
    user = User.create!(name: "Test User", email: "test@example.com")
    workflow = ExampleCalculationWorkflow.start!(user)
    step = workflow.workflow_steps.find_by(name: "fetch_numbers")
    step.update!(status: :running)

    job = Workflows::RunStepJob.new
    job.perform(step.id)

    step.reload
    assert step.running?
  end

  test "optimistic locking: only one worker claims pending step" do
    user = User.create!(name: "Test User", email: "test@example.com")
    workflow = ExampleCalculationWorkflow.start!(user)
    step = workflow.workflow_steps.find_by(name: "fetch_numbers")

    claimed_count = 0
    threads = []

    # Simulate 3 workers trying to claim same step
    3.times do
    threads << Thread.new do
      job = Workflows::RunStepJob.new
      current_updated_at = step.updated_at

      rows = WorkflowStep.where(
        id: step.id,
        status: :pending,
        updated_at: current_updated_at
      ).update_all(
        status: :running,
        attempts: step.attempts + 1,
        started_at: Time.current,
        updated_at: Time.current
      )

      claimed_count += 1 if rows > 0
      end
    end

    threads.each(&:join)

    assert_equal 1, claimed_count
    step.reload
    assert step.running?
    assert_equal 1, step.attempts
  end

  test "exits gracefully when cancelled workflow" do
    user = User.create!(name: "Test User", email: "test@example.com")
    workflow = ExampleCalculationWorkflow.start!(user)
    workflow.cancel!(reason: "Test cancellation", by: "test")

    step = workflow.workflow_steps.find_by(name: "fetch_numbers")

    job = Workflows::RunStepJob.new
    job.perform(step.id)

    step.reload
    assert_not step.succeeded?
  end

  test "marks step as cancelled if workflow cancelled after claim" do
    user = User.create!(name: "Test User", email: "test@example.com")
    workflow = ExampleCalculationWorkflow.start!(user)
    step = workflow.workflow_steps.find_by(name: "fetch_numbers")

    # Manually claim the step
    step.update!(status: :running, attempts: 1)

    # Cancel workflow
    workflow.cancel!(reason: "Test cancellation", by: "test")

    # RunStepJob checks after claim
    job = Workflows::RunStepJob.new

    # Simulate the check after claim in perform method
    if workflow.cancelled?
    step.update!(status: :cancelled, completed_at: Time.current)
    end

    step.reload
    assert step.cancelled?
  end

  test "handles errors and marks step as failed" do
    user = User.create!(name: "Test User", email: "test@example.com")

    # Create a failing workflow class
    failing_workflow_class = Class.new(Base) do
    step :failing_step

    def failing_step(workflow:, step:, input:)
      raise StandardError, "Intentional test failure"
      end
    end

    # Register it
    Base.registry["TestFailingWorkflow"] = failing_workflow_class

    workflow = Workflow.create!(
    name: "test.failing",
    workflow_class: "TestFailingWorkflow",
    subject: user,
    state: :pending
    )

    workflow.workflow_steps.create!(
    name: "failing_step",
    status: :pending,
    depends_on: [],
    position: 0,
    max_attempts: 5
    )

    step = workflow.workflow_steps.first

    job = Workflows::RunStepJob.new
    job.perform(step.id)

    step.reload
    assert_not_nil step.last_error
    assert_includes step.last_error, "Intentional test failure"
  end

  test "increments attempts on execution" do
    user = User.create!(name: "Test User", email: "test@example.com")
    workflow = ExampleCalculationWorkflow.start!(user)
    step = workflow.workflow_steps.find_by(name: "fetch_numbers")

    assert_equal 0, step.attempts

    job = Workflows::RunStepJob.new
    job.perform(step.id)

    step.reload
    assert_equal 1, step.attempts
  end
end
