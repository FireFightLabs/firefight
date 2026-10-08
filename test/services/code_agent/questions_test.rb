require "test_helper"

# A coding agent asks a question through its bridge, the question shows in the chat's thread, and Halon or the person
# who asked for the change answers it, and the agent carries on with the answer.
class CodeAgent::QuestionsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @conversation = @workspace.conversations.create!(kind: Conversation::KIND_CHANNEL, started_by: @bob, channel_id: "C9", thread_id: "5.5",
                                                     max_turns: 5, max_spend_cents: 100)
    @conversation.chat_record
    request = CodeAgent::Request.new(principal: @bob, source: AbilityGateway::SOURCE_CONVERSATION, place: @conversation, tool_call_id: "call_1")
    @session, @token = CodeAgentSession.open!(workspace: @workspace, choice: FirefightAi::ModelChoice.new(model: "gpt-4o", provider: "openai"),
                                              repository: "acme/api", request: request)
    @adapter = stub(update_code_question: { success: true })
    WorkspaceAdapter.stubs(:for).returns(@adapter)
    CodeAgent::QuestionTools.stubs(:pause)
  end

  test "a question shows in the thread, the person answers it from the dashboard, and the agent carries on with the answer" do
    FirefightAi::QuestionAnswerer.any_instance.expects(:answer).with { |question:, **| question == "Tag or commit?" }.returns(nil)
    @adapter.expects(:post_code_question).with { |channel_id:, thread_id:, question:| channel_id == "C9" && thread_id == "5.5" && question.question == "Tag or commit?" }
            .returns(channel_id: "C9", message_id: "5.6")
    CodeAgent::QuestionTools.stubs(:clock).returns(0, 0, 100)

    perform_enqueued_jobs { ask("Tag or commit?") }

    assert_equal CodeAgent::QuestionTools::STILL_WAITING, said
    question = @session.questions.sole
    assert_equal [ "C9", "5.6", CodeAgentQuestion::STATUS_OPEN ], [ question.message_channel_id, question.message_id, question.status ]

    sign_in(@bob.user, @workspace)
    @adapter.expects(:update_code_question).with { |message_id:, question:, **| message_id == "5.6" && question.answered? }.returns(success: true)
    post code_agent_question_answer_path(question), params: { answer: "Send the tag." }
    assert_equal CodeAgentQuestionService::ANSWERED, flash[:notice]

    CodeAgent::QuestionTools.stubs(:clock).returns(0)
    call_bridge(CodeAgent::QuestionTools::WAIT)
    assert_equal "Bob Jones answered: Send the tag.", said
  end

  test "Halon answers first when what it read settles the question, and nobody else is asked" do
    FirefightAi::QuestionAnswerer.any_instance.expects(:answer).returns("The tag, as the person said in their second message.")
    @adapter.stubs(:post_code_question).returns(channel_id: "C9", message_id: "5.6")
    CodeAgent::QuestionTools.stubs(:clock).returns(0)

    perform_enqueued_jobs { ask("Tag or commit?") }
    call_bridge(CodeAgent::QuestionTools::WAIT)

    assert_equal "Halon answered: The tag, as the person said in their second message.", said
    assert @session.questions.sole.by_halon?
  end

  test "only the person the change runs as can answer, and a second question waits for the first" do
    @adapter.stubs(:post_code_question).returns(channel_id: "C9", message_id: "5.6")
    question = CodeAgentQuestion.ask!(@session, "Tag or commit?")

    sign_in(@alice.user, @workspace)
    post code_agent_question_answer_path(question), params: { answer: "The commit." }

    assert_equal "Only Bob Jones can answer, since the change runs as them.", flash[:alert]
    assert question.reload.open?
    assert_raises(CodeAgentQuestion::Refused) { CodeAgentQuestion.ask!(@session, "And the branch?") }
  end

  test "a question past its time ends, and the agent is told to stop and change nothing more" do
    question = CodeAgentQuestion.ask!(@session, "Tag or commit?")
    @adapter.expects(:update_code_question).with { |question:, **| question.expired? }.returns(success: true)
    question.update_columns(message_channel_id: "C9", message_id: "5.6")
    CodeAgent::QuestionTools.stubs(:clock).returns(0)

    travel CodeAgentQuestion::ANSWER_WITHIN + 1.second do
      perform_enqueued_jobs { call_bridge(CodeAgent::QuestionTools::WAIT) }
    end

    assert_equal "Nobody answered within 5 minutes. Stop now, change nothing more, and end with your question in your summary.", said
    assert question.reload.expired?
    assert_not question.answer!("Too late", by: @bob)
  end

  private

  def ask(text) = call_bridge(CodeAgent::QuestionTools::ASK, question: text)

  def call_bridge(name, **arguments)
    post "/code_agent/tools", params: { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: name, arguments: arguments } }.to_json,
                              headers: { "Authorization" => "Bearer #{@token}", "CONTENT_TYPE" => "application/json" }
  end

  def said = response.parsed_body.dig("result", "content", 0, "text")
end
