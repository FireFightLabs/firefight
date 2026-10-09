require "test_helper"

class CodeAgentSessionTest < ActiveSupport::TestCase
  test "the token is kept only as a digest, and stops working when the session ends or expires" do
    session, token = CodeAgentSession.open!(workspace: workspaces(:slack_workspace_one),
                                             choice: FirefightAi::ModelChoice.new(model: "gpt-4o", provider: "openai"), repository: "acme/api")

    assert_not_equal token, session.token_digest
    assert_equal session, CodeAgentSession.authenticate(token)
    assert_nil CodeAgentSession.authenticate("other")

    travel CodeAgentSession::LIFETIME + 1.minute
    assert_nil CodeAgentSession.authenticate(token)
  end

  test "two calls charged at once are both counted" do
    session, = CodeAgentSession.open!(workspace: workspaces(:slack_workspace_one),
                                      choice: FirefightAi::ModelChoice.new(model: "gpt-4o", provider: "openai"), repository: "acme/api")
    stale = CodeAgentSession.find(session.id)

    session.charge!(300)
    stale.charge!(200)

    assert_equal 500, session.reload.spent_micros
  end

  test "a call refused for credit on the deployment's keys is the house's, and one on the workspace's own account is not" do
    workspace = workspaces(:slack_workspace_one)
    choice = FirefightAi::ModelChoice.new(model: "gpt-4o", provider: "openai")
    house, = CodeAgentSession.open!(workspace: workspace, choice: choice, repository: "acme/api")
    assert_not house.house_refused_for_credit?

    Inference.create!(workspace: workspace, feature: CodeAgentSession::FEATURE, provider: "openai", model: "gpt-4o", inferable: house,
                      status: Inference::STATUS_ERROR, error_kind: Inference::ERROR_OUT_OF_CREDIT, **house.payer.ledger)
    assert house.house_refused_for_credit?

    house.update_columns(paid_by: Inference::PAID_BY_ACCOUNT, workspace_ai_account_id: add_ai_account!(workspace).id)
    assert_not house.reload.house_refused_for_credit?
  end
end
