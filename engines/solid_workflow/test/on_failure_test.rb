require_relative "test_helper"

# A class workflow whose first step fails, with a step after it that records it ran.
class ContinuingWorkflow < SolidWorkflow::Base
  workflow_name "test.continuing"

  step :flaky, retry_config: { max_attempts: 1 }, on_failure: SolidWorkflow::Definition::ON_FAILURE_CONTINUE
  step :after, depends_on: [ :flaky ]

  def flaky(workflow:, step:, input:) = raise("it failed")
  def after(workflow:, step:, input:) = { "ran" => true }
end

class StoppingWorkflow < SolidWorkflow::Base
  workflow_name "test.stopping"

  step :flaky, retry_config: { max_attempts: 1 }
  step :after, depends_on: [ :flaky ]

  def flaky(workflow:, step:, input:) = raise("it failed")
  def after(workflow:, step:, input:) = { "ran" => true }
end

class ErrorRouteWorkflow < SolidWorkflow::Base
  workflow_name "test.error_route"

  step :only, on_failure: SolidWorkflow::Definition::ON_FAILURE_ERROR_ROUTE

  def only(workflow:, step:, input:) = {}
end

class SolidWorkflow::OnFailureTest < ActiveSupport::TestCase
  setup do
    @subject = User.create!(name: "On Failure User", email: "of-#{SecureRandom.hex(4)}@example.com")
  end

  test "a class step set to continue lets what depends on it run once it has failed for good, and the run carries on" do
    workflow = ContinuingWorkflow.start_inline!(@subject)

    assert workflow.succeeded?
    assert workflow.steps.find_by!(name: "flaky").failed?
    assert_equal({ "ran" => true }, workflow.steps.find_by!(name: "after").output)
  end

  test "a class step that stops, the default, fails the run and cancels what depends on it" do
    workflow = StoppingWorkflow.start_inline!(@subject)

    assert workflow.failed?
    assert_equal "stop", workflow.steps.find_by!(name: "flaky").on_failure
    assert workflow.steps.find_by!(name: "after").cancelled?
  end

  test "a step that is still to retry holds back what depends on it" do
    workflow = ContinuingWorkflow.start!(@subject)
    flaky, after = workflow.steps.find_by!(name: "flaky"), workflow.steps.find_by!(name: "after")
    flaky.update!(status: :pending, attempts: 1, run_at: 1.minute.from_now)

    assert_not after.reload.ready_to_run?(workflow.steps.reload.to_a)
  end

  test "a class step can only stop or continue, since it has no error route" do
    error = assert_raises(ArgumentError) { ErrorRouteWorkflow.start!(@subject) }

    assert_match "on_failure 'error_route'", error.message
  end
end
