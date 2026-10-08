require "test_helper"

class Slack::WorkspaceAdapter::AgentStepsTest < ActiveSupport::TestCase
  setup do
    @adapter = Slack::WorkspaceAdapter.new(workspaces(:slack_workspace_one))
    @sent = []
    Slack::Client.stubs(:append_stream).with { |chunks:, **| @sent.concat(chunks) }.returns({})
  end

  test "a step one of Firefight's own rules refused ends complete and says Refused, while a failure is an error" do
    @adapter.report_agent_step(channel_id: "C1", answer_id: "1.2", key: "call_1", title: "Github fix code", status: :done,
                               outcome: Chat::StepOutcome::KIND_REFUSED)
    @adapter.report_agent_step(channel_id: "C1", answer_id: "1.2", key: "call_2", title: "Github fix code", status: :done,
                               outcome: Chat::StepOutcome::KIND_FAILED)

    assert_equal [ [ "complete", "Refused" ], [ "error", "Failed" ] ], @sent.map { |task| task.values_at(:status, :output) }
  end
end
