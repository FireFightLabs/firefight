require "test_helper"

# A coding agent asks a question through its bridge, the question shows in the chat's thread, and Halon or the person
# who asked for the change answers it, and the agent carries on with the answer.
class CodeAgent::QuestionsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include CodeQuestionTestHelper

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
    FirefightAi::QuestionAnswerer.any_instance.expects(:answer)
                               .returns(FirefightAi::QuestionAnswerer::Reply.new(text: "The tag, as the person said in their second message.", option: nil))
    @adapter.stubs(:post_code_question).returns(channel_id: "C9", message_id: "5.6")
    CodeAgent::QuestionTools.stubs(:clock).returns(0)

    perform_enqueued_jobs { ask("Tag or commit?") }
    call_bridge(CodeAgent::QuestionTools::WAIT)

    assert_equal "Halon answered: The tag, as the person said in their second message.", said
    assert @session.questions.sole.by_halon?
  end

  test "only the person the change runs as can answer, and a second question waits for the first" do
    @adapter.stubs(:post_code_question).returns(channel_id: "C9", message_id: "5.6")
    question = ask_question!(@session, "Tag or commit?")

    sign_in(@alice.user, @workspace)
    post code_agent_question_answer_path(question), params: { answer: "The commit." }

    assert_equal "Only Bob Jones can answer, since the change runs as them.", flash[:alert]
    assert question.reload.open?
    assert_raises(CodeAgentQuestion::Refused) { ask_question!(@session, "And the branch?") }
  end

  test "a question past its time with nothing to fall back on ends, and the agent is told to stop and change nothing more" do
    question = ask_question!(@session, "Tag or commit?")
    question.update_columns(options: nil, recommended: nil)
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

  test "a question past its time goes with the recommendation, and the agent is told to carry on with it and say so" do
    question = ask_question!(@session, "Tag or commit?")
    @adapter.expects(:update_code_question).with { |question:, **| question.defaulted? }.returns(success: true)
    question.update_columns(message_channel_id: "C9", message_id: "5.6")
    CodeAgent::QuestionTools.stubs(:clock).returns(0)

    travel CodeAgentQuestion::ANSWER_WITHIN + 1.second do
      perform_enqueued_jobs { call_bridge(CodeAgent::QuestionTools::WAIT) }
    end

    assert_equal "Nobody answered within 5 minutes, so go with your recommendation: Send the tag. Northflank names the run after the " \
                 "release, such as v1.4.0. Say in your summary that it was not answered and what you went with.", said
    assert_equal [ CodeAgentQuestion::STATUS_DEFAULTED, 0 ], question.reload.values_at(:status, :chosen)
    assert_nil @session.unanswered_question, "a change that went with the recommendation carries on"
  end

  test "a question needs two to four options with what each leads to, a recommendation among them and why" do
    assert_match "Give 2 to 4 options", assert_raises(CodeAgentQuestion::Refused) { ask_question!(@session, "Tag?", options: TAG_OR_COMMIT.first(1)) }.message
    no_consequence = [ { "label" => "Tag" }, { "label" => "Commit", "consequence" => "Named after the commit." } ]
    assert_raises(CodeAgentQuestion::Refused) { ask_question!(@session, "Tag or commit?", options: no_consequence) }
    assert_match "Name the option you recommend", assert_raises(CodeAgentQuestion::Refused) { ask_question!(@session, "Tag or commit?", recommended: "Neither") }.message
    assert_match "why you recommend it", assert_raises(CodeAgentQuestion::Refused) { ask_question!(@session, "Tag or commit?", reason: " ") }.message

    question = ask_question!(@session, "Tag or commit?", recommended: "send the commit")
    assert_equal [ 1, "Send the commit" ], [ question.recommended, question.recommended_option.label ]
  end

  test "the agent is told to check the code, recommend what matches it and the person, and write the question plainly with a real example" do
    tool = CodeAgent::QuestionTools.for(@session).find { |each| each.name_value == CodeAgent::QuestionTools::ASK }
    description = tool.description_value
    assert_match "read the code for how the app already behaves in the same situation", description
    assert_match "recommend the option most consistent with the existing behaviour and the person's own words", description
    assert_match "Nobody answering within 5 minutes means your recommendation", description
    assert_match "never placeholders such as team T or team A", description
    assert_match "Today Firefight offers to create a new workspace for Side Project", description
    assert_equal %w[question options recommended reason], tool.input_schema_value.to_h[:required]
  end

  private

  def ask(text) = call_bridge(CodeAgent::QuestionTools::ASK, question: text, options: TAG_OR_COMMIT, recommended: TAG_OR_COMMIT.first["label"], reason: TAG_REASON)

  def call_bridge(name, **arguments)
    post "/code_agent/tools", params: { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: name, arguments: arguments } }.to_json,
                              headers: { "Authorization" => "Bearer #{@token}", "CONTENT_TYPE" => "application/json" }
  end

  def said = response.parsed_body.dig("result", "content", 0, "text")
end
