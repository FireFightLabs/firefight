require "test_helper"

class Investigation::RemediationStepOutcomeTest < ActiveSupport::TestCase
  PULL = "https://github.com/FireFightLabs/firefight/pull/856".freeze

  test "a code change's pull request is its outcome, from the tool's words or the coding agent's record" do
    said = "Opened #{PULL} on FireFightLabs/firefight against main.\n\nChecks: running"

    assert_equal [ "PR #856", PULL ], Investigation::RemediationStep::Outcome.of(said, nil)
    work = Chat::CodeFixProgress.new(started_at: Time.current)
    work.opened!(files: {}, pull_request: "#{PULL}/")
    assert_equal [ "PR #856", "#{PULL}/" ], Investigation::RemediationStep::Outcome.of("Done.", work)
  end

  test "any other address the tool answered with is a link, and a step that gave none has no outcome" do
    said = "Rolled back to deploy 41. See https://app.northflank.com/s/team/project/services/web/deployments."

    assert_equal [ "app.northflank.com/s/team/project/services/web/deployments", "https://app.northflank.com/s/team/project/services/web/deployments" ],
                 Investigation::RemediationStep::Outcome.of(said, nil)
    assert_nil Investigation::RemediationStep::Outcome.of("Rule deleted", nil)
  end

  test "a step is Firefight's own tool only when it was written as one, never by a connection's tool sharing its name" do
    assert_not Investigation::RemediationStep.new(kind: Investigation::RemediationStep::KIND_ACTION, tool_name: Mcp::Tools::INVITE_RESPONDERS).firefight_tool?
    assert Investigation::RemediationStep.new(kind: Investigation::RemediationStep::KIND_ACTION, tool_name: Mcp::Tools::INVITE_RESPONDERS, firefight_tool: true).firefight_tool?
  end

  test "a step's line says what it produced or why it was already done" do
    code = Investigation::RemediationStep.new(kind: Investigation::RemediationStep::KIND_PULL_REQUEST, status: Investigation::RemediationStep::STATUS_DONE,
                                              outcome_label: "PR #856", outcome_url: PULL)
    assert_equal "Opened a pull request: PR #856", code.result_line

    invite = Investigation::RemediationStep.new(kind: Investigation::RemediationStep::KIND_ACTION, status: Investigation::RemediationStep::STATUS_DONE,
                                                already_done_reason: "Uros Nikolic is already in #inc-003")
    assert_equal "Already done: Uros Nikolic is already in #inc-003", invite.result_line
    assert_nil Investigation::RemediationStep.new(kind: Investigation::RemediationStep::KIND_ACTION).result_line
  end
end
