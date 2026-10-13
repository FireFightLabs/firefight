require "test_helper"

class Operator::ActionsTest < ActiveSupport::TestCase
  test "a run parked on a waiting step can be paused and cancelled from the console" do
    user = User.create!(name: "Console User", email: "console-#{SecureRandom.hex(3)}@example.com")
    workflow = ExampleCalculationWorkflow.start!(user)
    workflow.update_columns(state: SolidWorkflow::Workflow.states.fetch("waiting"))

    assert_nil Operator::Actions.pause_blocked_reason(workflow)
    assert_nil Operator::Actions.cancel_blocked_reason(workflow)
    assert_equal "Only a paused workflow can be resumed.", Operator::Actions.resume_blocked_reason(workflow)
  end
end
