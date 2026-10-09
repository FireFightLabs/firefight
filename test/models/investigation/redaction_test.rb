require "test_helper"

# What a run shows of a provider's answer or error never carries a password in a connection string.
class Investigation::RedactionTest < ActiveSupport::TestCase
  CONNECTION = "postgres://app:hunter2@db.internal:5432/orders".freeze

  setup do
    @investigation = workspaces(:slack_workspace_one).investigations.create!(
      subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400
    )
  end

  test "a remediation step's stored text drops a connection string's password" do
    redacted = Investigation::RemediationStep.redacted("Connected with #{CONNECTION}")

    assert_not_includes redacted, "hunter2"
    assert_nil Investigation::RemediationStep.redacted(nil)
  end

  test "a step that raised keeps its error without a connection string's password" do
    step = @investigation.steps.create!(position: 1, tool_name: "query_database", status: Investigation::Step::STATUS_RUNNING)

    step.fail!(RuntimeError.new("could not connect to #{CONNECTION}"))

    assert_match "RuntimeError: could not connect to", step.reload.error_summary
    assert_not_includes step.error_summary, "hunter2"
  end
end
