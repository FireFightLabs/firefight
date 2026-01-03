require "test_helper"

class Workflows::OrchestrateJobTest < ActiveSupport::TestCase
  test "finds and enqueues ready steps" do
    user = User.create!(name: "Test User", email: "test@example.com")
    workflow = ExampleCalculationWorkflow.start!(user)

    # Mark first step as succeeded
    fetch_numbers = workflow.workflow_steps.find_by(name: "fetch_numbers")
    fetch_numbers.update!(status: :succeeded, output: { numbers: [ 1, 2, 3 ] })

    # Orchestrate
    job = Workflows::OrchestrateJob.new
    job.perform(workflow.id)

    # Both parallel steps should become ready (input populated)
    calculate_sum = workflow.workflow_steps.find_by(name: "calculate_sum")
    calculate_product = workflow.workflow_steps.find_by(name: "calculate_product")

    calculate_sum.reload
    calculate_product.reload

    assert_not_nil calculate_sum.input
    assert_not_nil calculate_product.input
    assert_equal({ "numbers" => [ 1, 2, 3 ] }, calculate_sum.input["fetch_numbers"])
    assert_equal({ "numbers" => [ 1, 2, 3 ] }, calculate_product.input["fetch_numbers"])
  end

  test "updates workflow state to running when first step starts" do
    user = User.create!(name: "Test User", email: "test@example.com")
    workflow = ExampleCalculationWorkflow.start!(user)

    # Manually set to pending
    workflow.update!(state: :pending)

    # Mark first step as running
    fetch_numbers = workflow.workflow_steps.find_by(name: "fetch_numbers")
    fetch_numbers.update!(status: :running)

    # Orchestrate
    job = Workflows::OrchestrateJob.new
    job.perform(workflow.id)

    workflow.reload
    assert workflow.running?
  end

  test "updates workflow state to succeeded when all steps succeeded" do
    user = User.create!(name: "Test User", email: "test@example.com")
    workflow = ExampleCalculationWorkflow.start!(user)

    # Mark all steps as succeeded
    workflow.workflow_steps.each do |step|
      step.update!(status: :succeeded, output: { result: "test" })
    end

    # Orchestrate
    job = Workflows::OrchestrateJob.new
    job.perform(workflow.id)

    workflow.reload
    assert workflow.succeeded?
  end

  test "updates workflow state to failed when step fails with max attempts" do
    user = User.create!(name: "Test User", email: "test@example.com")
    workflow = ExampleCalculationWorkflow.start!(user)

    # Mark first step as failed with max attempts
    fetch_numbers = workflow.workflow_steps.find_by(name: "fetch_numbers")
    fetch_numbers.update!(status: :failed, attempts: 5, max_attempts: 5)

    # Orchestrate
    job = Workflows::OrchestrateJob.new
    job.perform(workflow.id)

    workflow.reload
    assert workflow.failed?
  end

  test "respects concurrency limit" do
    user = User.create!(name: "Test User", email: "test@example.com")

    # Create workflow with concurrency limit
    parallel_workflow = Class.new(Base) do
      workflow_config max_concurrent_steps: 2

      step :step1
      step :step2
      step :step3
      step :step4

      def step1(**); { result: 1 }; end
      def step2(**); { result: 2 }; end
      def step3(**); { result: 3 }; end
      def step4(**); { result: 4 }; end
    end

    Base.registry["TestParallelWorkflow"] = parallel_workflow

    workflow = Workflow.create!(
      name: "test.parallel",
      workflow_class: "TestParallelWorkflow",
      subject: user,
      state: :pending,
      workflow_config: { max_concurrent_steps: 2 }
    )

    # Create 4 steps, all ready to run
    4.times do |i|
      workflow.workflow_steps.create!(
        name: "step#{i + 1}",
        status: :pending,
        depends_on: [],
        position: i,
        max_attempts: 5
      )
    end

    # Orchestrate
    job = Workflows::OrchestrateJob.new
    job.perform(workflow.id)

    # Only 2 steps should have input populated (concurrency limit)
    steps_with_input = workflow.workflow_steps.reload.count { |s| s.input.present? }
    assert_operator steps_with_input, :<=, 2
  end

  test "optimistic locking prevents duplicate enqueues" do
    user = User.create!(name: "Test User", email: "test@example.com")
    workflow = ExampleCalculationWorkflow.start!(user)

    # Mark first step as succeeded
    fetch_numbers = workflow.workflow_steps.find_by(name: "fetch_numbers")
    fetch_numbers.update!(status: :succeeded, output: { numbers: [ 1, 2, 3 ] })

    enqueued_count = 0
    threads = []

    # Simulate 2 orchestrators running concurrently
    2.times do
      threads << Thread.new do
        workflow.reload
        steps = workflow.workflow_steps.reload.to_a

        step_map = steps.index_by(&:name)
        ready = steps.select { |s| s.ready_to_run?(step_map) }

        ready.each do |step|
          step.populate_input_data(steps)
        end

        # Try to update inputs (optimistic locking)
        ready.each do |step|
          next unless step.changed?

          rows = WorkflowStep.where(
            id: step.id,
            status: step.status_was,
            updated_at: step.updated_at_was
          ).update_all(
            input: step.input,
            updated_at: Time.current
          )

          enqueued_count += 1 if rows > 0
        end
      end
    end

    threads.each(&:join)

    # Should only enqueue once per step (2 parallel steps = 2 total)
    assert_equal 2, enqueued_count
  end
end
