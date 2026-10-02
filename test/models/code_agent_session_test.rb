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
end
