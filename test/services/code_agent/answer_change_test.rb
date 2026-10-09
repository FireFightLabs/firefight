require "test_helper"

# Once a coding agent's question is answered, by Halon, by the person or by the clock, the person the change runs as can
# change the answer while the change is still written, and the agent is sent the new one as a correction with its next
# call, whichever of Firefight's tools that is.
class CodeAgent::AnswerChangeTest < ActionDispatch::IntegrationTest
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
    @question = ask_question!(@session, "Tag or commit?")
    @question.update_columns(message_channel_id: "C9", message_id: "5.6")
    @adapter = stub(update_code_question: { success: true })
    WorkspaceAdapter.stubs(:for).returns(@adapter)
    CodeAgent::QuestionTools.stubs(:pause)
    CodeAgent::QuestionTools.stubs(:clock).returns(0)
  end

  test "only the person the change runs as changes a settled answer, only while the change is written, never one still waiting" do
    assert_equal "This question is still waiting for an answer, so answer it rather than change it.", @question.change_answer_blocked_reason(@bob)

    assert @question.answer_as_halon!("The tag, as Bob said.", option: 0)
    assert_nil @question.change_answer_blocked_reason(@bob)
    assert_equal "Only Bob Jones can answer, since the change runs as them.", @question.change_answer_blocked_reason(@alice)
    assert_equal "Only Bob Jones can answer, since the change runs as them.", @question.change_answer_blocked_reason(nil)
    assert @question.to_h["changeable"], "Change answer is offered to everyone, and disabled with the reason for anyone but Bob"

    @session.open_push!(5.minutes)
    assert_equal "The change this question was for has finished, so its answer can no longer change.", @question.reload.change_answer_blocked_reason(@bob)
    @session.close_push!
    assert_nil @question.reload.change_answer_blocked_reason(@bob)

    @session.close!
    assert_equal "The change this question was for has finished, so its answer can no longer change.", @question.reload.change_answer_blocked_reason(@bob)
    assert_not @question.to_h["changeable"]
  end

  test "an answer that went with the recommendation can be changed too, and one that ended the change cannot" do
    @question.update_columns(answer_due_at: 1.minute.ago)
    assert @question.expire_if_overdue!
    assert @question.defaulted?
    assert_nil @question.change_answer_blocked_reason(@bob)
    assert_equal "Send the tag", @question.current_answer

    @question.update_columns(status: CodeAgentQuestion::STATUS_WITHDRAWN)
    assert_equal "The change this question was for has ended.", @question.reload.change_answer_blocked_reason(@bob)
  end

  test "a change is one guarded update, so two at once leave one standing and none lands once the change finished" do
    @question.answer_as_halon!("The tag.", option: 0)
    first = CodeAgentQuestion.find(@question.id)
    second = CodeAgentQuestion.find(@question.id)

    assert first.change_answer!(nil, by: @bob, option: 1)
    assert_not second.change_answer!("Send both.", by: @bob)
    assert_equal [ 1, "Send the commit", @bob ], @question.reload.values_at(:changed_chosen, :changed_answer, :changed_by)

    stale = CodeAgentQuestion.find(@question.id)
    @session.close!
    assert_not stale.change_answer!("Send both.", by: @bob)
    assert_equal "Send the commit", @question.reload.changed_answer
  end

  test "Halon's answer is used at once, and a changed one reaches the agent at its next wait as a correction that replaces it" do
    @question.answer_as_halon!("The tag, as Bob said.", option: 0)
    call_bridge(CodeAgent::QuestionTools::WAIT)
    assert_equal "Halon chose: Send the tag. Northflank names the run after the release, such as v1.4.0. The tag, as Bob said.", said

    sign_in(@bob.user, @workspace)
    @adapter.expects(:update_code_question).with { |message_id:, question:, **| message_id == "5.6" && question.changed_chosen == 1 }.returns(success: true)
    post code_agent_question_change_path(@question), params: { option: 1 }
    assert_equal CodeAgentQuestionService::CHANGED, flash[:notice]

    call_bridge(CodeAgent::QuestionTools::WAIT)
    assert_equal "The person changed their answer to your question \"Tag or commit?\". This replaces the earlier answer. Bob Jones chose: Send the commit. " \
                 "Northflank names the run after the commit, such as 3f2a9c1. Follow this answer from now on, and undo anything you did only because of the earlier one.",
                 said
    assert_equal 1, response.parsed_body.dig("result", "content").size

    call_bridge(CodeAgent::QuestionTools::WAIT)
    assert_equal "Bob Jones chose: Send the commit. Northflank names the run after the commit, such as 3f2a9c1.", said, "a correction is sent once"
  end

  test "an agent that never waits again gets the changed answer with whatever tool it calls next, once" do
    @question.answer_as_halon!("The tag.", option: 0)
    assert CodeAgentQuestionService.change!(@question, "Send both, the tag first.", by: @bob).ok

    call_bridge(CodeAgent::ReadTools::LIST)
    texts = response.parsed_body.dig("result", "content").map { |part| part["text"] }
    assert_equal 2, texts.size, response.body
    assert_match "Bob Jones answered: Send both, the tag first.", texts.last
    assert_match "This replaces the earlier answer.", texts.last

    call_bridge(CodeAgent::ReadTools::LIST)
    assert_equal 1, response.parsed_body.dig("result", "content").size
  end

  test "an answer changed again while the agent was being sent the earlier change waits for its next call rather than being lost" do
    @question.answer_as_halon!("The tag.", option: 0)
    @question.change_answer!(nil, by: @bob, option: 1)
    read = CodeAgentQuestion.correction_waiting.where(session: @session).to_a
    travel(1.second) { CodeAgentQuestion.find(@question.id).change_answer!("Send both.", by: @bob) }

    assert_equal 0, CodeAgentQuestion.where(id: read.first.id, changed_at: read.first.changed_at).update_all(correction_sent_for: read.first.changed_at)
    assert_equal [ @question ], CodeAgentQuestion.claim_corrections!(@session)
    assert_match "Bob Jones answered: Send both.", @question.reload.correction_words
    assert_empty CodeAgentQuestion.claim_corrections!(@session)
  end

  test "the dashboard refuses the same answer, both an option and words, an empty change, and anyone the change does not run as" do
    @question.answer!("Send the tag.", by: @bob, option: 0)
    sign_in(@alice.user, @workspace)
    post code_agent_question_change_path(@question), params: { option: 1 }
    assert_equal "Only Bob Jones can answer, since the change runs as them.", flash[:alert]

    sign_in(@bob.user, @workspace)
    post code_agent_question_change_path(@question), params: { option: 0 }
    assert_equal CodeAgentQuestionService::SAME, flash[:alert]
    post code_agent_question_change_path(@question), params: { option: 1, answer: "Both." }
    assert_equal CodeAgentQuestionService::CHANGE_BOTH, flash[:alert]
    post code_agent_question_change_path(@question), params: { answer: " " }
    assert_equal CodeAgentQuestionService::CHANGE_EMPTY, flash[:alert]
    post code_agent_question_change_path(@question), params: { option: 7 }
    assert_equal CodeAgentQuestionService::NO_SUCH_OPTION, flash[:alert]
    assert_not @question.reload.changed?

    post code_agent_question_change_path(@question), params: { answer: "Send both." }
    assert_equal CodeAgentQuestionService::CHANGED, flash[:notice]
    assert_equal [ "Send both.", nil, @bob ], @question.reload.values_at(:changed_answer, :changed_chosen, :changed_by)
    ledgered = Ability::Invocation.where(workspace: @workspace, action_key: Ability::Action::INVESTIGATIONS_CREATE, source: AbilityGateway::SOURCE_WEB)
    assert(ledgered.any? { |row| row.params["path"] == code_agent_question_change_path(@question) })
  end

  test "the step shows the question as it stands now, with Changed to and who may change it, though the step last reported it earlier" do
    @question.answer_as_halon!("The tag.", option: 0)
    work = Chat::CodeFixProgress.start
    work.asked!(@question.to_h)
    @question.change_answer!(nil, by: @bob, option: 1)

    current = work.with_current_question(@workspace.id)
    assert_equal [ "Send the commit", "Bob Jones", 1 ], current.question.values_at("changedTo", "changedBy", "changedChosen")
    assert_nil current.question_change_blocked_reason(@workspace.id, @bob)
    assert_equal "Only Bob Jones can answer, since the change runs as them.", current.question_change_blocked_reason(@workspace.id, @alice)
  end

  private

  def call_bridge(name, **arguments)
    post "/code_agent/tools", params: { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: name, arguments: arguments } }.to_json,
                              headers: { "Authorization" => "Bearer #{@token}", "CONTENT_TYPE" => "application/json" }
  end

  def said = response.parsed_body.dig("result", "content", 0, "text")
end
