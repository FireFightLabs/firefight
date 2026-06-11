require "test_helper"

class SolidWorkflow::EngineHardeningTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Workflow Hardening User", email: "wh-#{SecureRandom.hex(4)}@example.com")
  end

  test "calculate_backoff adds jitter so concurrent retries don't synchronize" do
    step = build_step(attempts: 2, retry_config: { "backoff" => "exponential" })

    delays = Array.new(20) { step.send(:calculate_backoff).to_f }
    assert delays.uniq.size > 1, "expected jittered delays, got identical: #{delays.first}"
    delays.each { |d| assert d.between?(1.0, 300.0) }
  end

  test "should_retry? returns false for terminal error classes" do
    step = build_step(attempts: 1, max_attempts: 5,
      last_error: "ActiveRecord::RecordNotFound: Couldn't find Foo")
    assert_not step.should_retry?

    step = build_step(attempts: 1, max_attempts: 5,
      last_error: "AdapterError::AuthRevoked: Platform auth revoked: token_revoked")
    assert_not step.should_retry?
  end

  test "should_retry? returns true for transient error with budget left" do
    step = build_step(attempts: 1, max_attempts: 3,
      last_error: "Net::ReadTimeout: execution expired")
    assert step.should_retry?
  end

  test "mark_failed! emits attempt_failed for transient and failed only on terminal" do
    workflow = ExampleCalculationWorkflow.start_inline!(@user, context: { numbers: [ 1, 2, 3 ] })
    step = workflow.steps.first

    step.update!(status: :running, attempts: 1, max_attempts: 3)
    workflow.events.where(event_type: SolidWorkflow::Events::Step::ATTEMPT_FAILED).delete_all
    workflow.events.where(event_type: SolidWorkflow::Events::Step::FAILED).delete_all

    step.mark_failed!(StandardError.new("transient"))
    assert_equal 1, workflow.events.where(event_type: SolidWorkflow::Events::Step::ATTEMPT_FAILED).count
    assert_equal 0, workflow.events.where(event_type: SolidWorkflow::Events::Step::FAILED).count

    step.update!(attempts: 3) # exhaust budget
    step.mark_failed!(StandardError.new("terminal"))
    assert_equal 1, workflow.events.where(event_type: SolidWorkflow::Events::Step::FAILED).count
  end

  test "format_error truncates very long messages" do
    workflow = ExampleCalculationWorkflow.start_inline!(@user, context: { numbers: [ 1, 2, 3 ] })
    step = workflow.steps.first

    huge = "x" * (SolidWorkflow::Step::Executable::MAX_ERROR_MESSAGE_BYTES + 5_000)
    error = StandardError.new(huge)
    error.set_backtrace([ "/app/file.rb:1:in `foo'" ])

    formatted = step.send(:format_error, error)
    assert_includes formatted, "[truncated]"
    assert formatted.bytesize < huge.bytesize + 200
  end

  test "Step#queue_name falls back to default when not set on retry_config" do
    step = build_step(retry_config: {})
    assert_equal SolidWorkflow.queue_name.to_s, step.queue_name

    step = build_step(retry_config: { "queue" => "ai" })
    assert_equal "ai", step.queue_name
  end

  class DummyQueuedWorkflow < SolidWorkflow::Base
    workflow_name "dummy.queued.v1"
    step :do_work, queue: :ai

    def do_work(workflow:, step:, input:)
      { ok: true }
    end
  end

  test "step DSL with queue: option stores queue on retry_config" do
    workflow = DummyQueuedWorkflow.start_inline!(@user)
    step = workflow.steps.find_by!(name: "do_work")
    assert_equal "ai", step.queue_name
  end

  test "populate_input_data emits warn log when input exceeds size cap" do
    workflow = ExampleCalculationWorkflow.start_inline!(@user, context: { numbers: [ 1, 2, 3 ] })
    step = workflow.steps.find_by!(name: "calculate_sum")

    parent = SolidWorkflow::Step.new(
      name: "fetch_numbers",
      status: "succeeded",
      workflow: workflow,
      output: { "blob" => "x" * (SolidWorkflow::Step::Dependencies::MAX_INPUT_BYTES + 5_000) }
    )

    Rails.logger.expects(:warn).with(has_entries(event: "workflow.step.input_size_exceeded")).at_least_once
    step.populate_input_data([ parent ], step_map: { "fetch_numbers" => parent })
  end

  test "Workflow.timed_out filters via SQL not Ruby" do
    workflow = ExampleCalculationWorkflow.start!(@user, context: { numbers: [ 1, 2, 3 ] })
    workflow.update!(
      state: :running,
      workflow_config: workflow.workflow_config.merge("timeout" => 1),
      started_at: 10.seconds.ago
    )

    sql = SolidWorkflow::Workflow.timed_out.to_sql
    assert_match(/EXTRACT\(EPOCH/, sql)
    assert_includes SolidWorkflow::Workflow.timed_out.pluck(:id), workflow.id
  end

  test "terminal-error step failure fails the workflow even with retry budget left" do
    workflow = ExampleCalculationWorkflow.start_inline!(@user, context: { numbers: [ 1, 2, 3 ] })
    workflow.update!(state: :running, completed_at: nil)
    step = workflow.steps.first
    step.update!(status: :running, attempts: 1, max_attempts: 5)

    step.mark_failed!(ActiveRecord::RecordNotFound.new("Couldn't find Foo"))
    assert step.reload.failed?

    workflow.enqueue_next_steps
    assert workflow.reload.failed?
  end

  test "retry_now! revives a failed workflow" do
    workflow = ExampleCalculationWorkflow.start_inline!(@user, context: { numbers: [ 1, 2, 3 ] })
    step = workflow.steps.first
    step.update!(status: :failed, attempts: 5, completed_at: Time.current)
    workflow.update!(state: :failed, completed_at: Time.current)

    step.retry_now!

    assert_not workflow.reload.failed?
    assert_nil workflow.completed_at
  end

  test "skip! revives a failed workflow" do
    workflow = ExampleCalculationWorkflow.start_inline!(@user, context: { numbers: [ 1, 2, 3 ] })
    step = workflow.steps.first
    step.update!(status: :failed, attempts: 5, completed_at: Time.current)
    workflow.update!(state: :failed, completed_at: Time.current)

    step.skip!(reason: "manual")

    assert step.reload.skipped?
    assert_not workflow.reload.failed?
  end

  test "sweeper fails an orphaned step that exhausted attempts instead of resetting it" do
    workflow = ExampleCalculationWorkflow.start!(@user, context: { numbers: [ 1, 2, 3 ] })
    workflow.update!(state: :running)
    step = workflow.steps.first
    step.update!(status: :running, attempts: 5, max_attempts: 5)
    step.update_column(:updated_at, (SolidWorkflow.orphaned_step_threshold + 1.minute).ago)

    SolidWorkflow::SweeperJob.new.send(:sweep_orphaned_steps)

    assert step.reload.failed?
    assert_includes step.last_error, "failed by sweeper"
  end

  test "sweeper still resets an orphaned step with attempts remaining" do
    workflow = ExampleCalculationWorkflow.start!(@user, context: { numbers: [ 1, 2, 3 ] })
    workflow.update!(state: :running)
    step = workflow.steps.first
    step.update!(status: :running, attempts: 1, max_attempts: 5)
    step.update_column(:updated_at, (SolidWorkflow.orphaned_step_threshold + 1.minute).ago)

    SolidWorkflow::SweeperJob.new.send(:sweep_orphaned_steps)

    assert step.reload.pending?
  end

  test "terminal_error_classes is engine config extended by the app initializer" do
    assert_includes SolidWorkflow.terminal_error_classes, "ActiveRecord::RecordNotFound"
    assert_includes SolidWorkflow.terminal_error_classes, "AdapterError::AuthRevoked"
  end

  class DuplicateStepWorkflow < SolidWorkflow::Base
    workflow_name "dummy.duplicate.v1"
    step :do_work
    step :do_work

    def do_work(workflow:, step:, input:) = { ok: true }
  end

  class UnknownDepWorkflow < SolidWorkflow::Base
    workflow_name "dummy.unknown_dep.v1"
    step :do_work, depends_on: [ :no_such_step ]

    def do_work(workflow:, step:, input:) = { ok: true }
  end

  class CyclicWorkflow < SolidWorkflow::Base
    workflow_name "dummy.cyclic.v1"
    step :a, depends_on: [ :b ]
    step :b, depends_on: [ :a ]

    def a(workflow:, step:, input:) = { ok: true }
    def b(workflow:, step:, input:) = { ok: true }
  end

  test "start! raises on duplicate step names" do
    error = assert_raises(ArgumentError) { DuplicateStepWorkflow.start!(@user) }
    assert_includes error.message, "duplicate step names: do_work"
  end

  test "start! raises on unknown dependency" do
    error = assert_raises(ArgumentError) { UnknownDepWorkflow.start!(@user) }
    assert_includes error.message, "unknown step(s): no_such_step"
  end

  test "start! raises on dependency cycle" do
    error = assert_raises(ArgumentError) { CyclicWorkflow.start!(@user) }
    assert_includes error.message, "dependency cycle"
  end

  private

  def build_step(attributes = {})
    workflow = ExampleCalculationWorkflow.start_inline!(@user, context: { numbers: [ 1, 2, 3 ] })
    workflow.steps.first.tap { |s| s.assign_attributes(attributes) }
  end
end
