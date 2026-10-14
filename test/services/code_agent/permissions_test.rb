require "test_helper"

# The box puts a step the coding agent asked permission for to Firefight, Halon decides it or asks the person where the
# change was asked for, and the box hears OpenCode's reply.
class CodeAgent::PermissionsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  REPEATED = { "tool" => "bash", "input" => { "command" => "bundle exec rspec spec/pool_spec.rb" } }.freeze
  LOOPING = "It edits the spec between runs, so each run tells it something new.".freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    @conversation = @workspace.conversations.create!(kind: Conversation::KIND_CHANNEL, started_by: @bob, channel_id: "C9", thread_id: "5.5",
                                                     max_turns: 5, max_spend_cents: 100)
    @conversation.chat_record
    @session, @token = open_session(place: @conversation)
    @adapter = stub(update_code_question: { success: true })
    WorkspaceAdapter.stubs(:for).returns(@adapter)
    CodeAgent::QuestionTools.stubs(:pause)
    CodeAgent::QuestionTools.stubs(:clock).returns(0, 100)
  end

  test "Halon lets a repeated step go on with why, from what the agent did lately, and the box hears once" do
    FirefightAi::PermissionJudge.any_instance.expects(:decide).with do |asked:, steps:, can_ask:, **|
      asked == "The coding agent repeated bash 3 times in a row with the same input: bundle exec rspec spec/pool_spec.rb" &&
        steps == [ "Ran bundle exec rspec spec/pool_spec.rb", "Edited spec/pool_spec.rb" ] && can_ask
    end.returns(decision(FirefightAi::PermissionJudge::ALLOW, LOOPING))

    perform_enqueued_jobs { ask }
    ask

    assert_equal CodeAgentPermission::REPLY_ONCE, response.parsed_body["reply"]
    permission = @session.permissions.sole
    assert permission.by_halon?
    assert_equal "OpenCode repeated bash 3 times in a row with the same input: bundle exec rspec spec/pool_spec.rb, and Halon let it continue " \
                 "because it edits the spec between runs, so each run tells it something new", permission.step_words
  end

  test "Halon stops a loop, and the box replies reject with why, which the agent reads" do
    FirefightAi::PermissionJudge.any_instance.expects(:decide).returns(decision(FirefightAi::PermissionJudge::STOP, "It ran the same command three times with the same result."))

    perform_enqueued_jobs { ask }
    ask

    assert_equal({ "reply" => CodeAgentPermission::REPLY_REJECT, "message" => "Halon refused this step. It ran the same command three times with the same result." },
                 response.parsed_body.except("permission"))
    assert_match "Halon stopped it because it ran the same command", @session.permissions.sole.step_words
  end

  test "the box asking again for the same request makes no second question and no second decision" do
    FirefightAi::PermissionJudge.any_instance.expects(:decide).once.returns(decision(FirefightAi::PermissionJudge::ALLOW, LOOPING))

    perform_enqueued_jobs { 3.times { ask } }

    assert_equal 1, @session.permissions.count
  end

  test "Halon leaves it to the person in the change's thread, the person stops it, and the answer cannot change once acted on" do
    FirefightAi::PermissionJudge.any_instance.expects(:decide).returns(decision(FirefightAi::PermissionJudge::ASK, "It may be waiting on a slow service.", lean: "allow"))
    FirefightAi::QuestionAnswerer.any_instance.expects(:answer).never
    @adapter.expects(:post_code_question).with { |question:, **| question.question.start_with?("The coding agent repeated bash 3 times") }.returns(channel_id: "C9", message_id: "5.6")

    perform_enqueued_jobs { ask }
    question = @session.questions.sole
    assert_equal [ CodeAgentPermission::ALLOW, CodeAgentPermission::STOP ], question.choices.map(&:label)
    assert_equal [ CodeAgentPermission::OPTION_ALLOW, "It may be waiting on a slow service." ], [ question.recommended, question.recommended_reason ]
    assert_nil @session.open_question, "it is not one of the agent's own questions"
    assert @session.count_question!, "nor does it count against them"

    sign_in(@bob.user, @workspace)
    post code_agent_question_answer_path(question), params: { option: CodeAgentPermission::OPTION_STOP }
    ask

    assert_equal CodeAgentPermission::REPLY_REJECT, response.parsed_body["reply"]
    assert @session.permissions.sole.step_words.end_with?(", and Bob Jones stopped it")
    assert_not question.reload.changeable?
    assert_equal "The coding agent already acted on this answer, so it can no longer change.", question.change_answer_blocked_reason(@bob)
  end

  test "nobody answering the person's question in time goes with the way Halon leaned" do
    FirefightAi::PermissionJudge.any_instance.expects(:decide).returns(decision(FirefightAi::PermissionJudge::ASK, "It may be waiting on a slow service.", lean: "allow"))
    @adapter.stubs(:post_code_question).returns(channel_id: "C9", message_id: "5.6")

    perform_enqueued_jobs { ask }
    travel CodeAgentQuestion::ANSWER_WITHIN + 1.second do
      perform_enqueued_jobs { ask }
    end

    assert_equal CodeAgentPermission::REPLY_ONCE, response.parsed_body["reply"]
    assert_match "Halon let it continue because nobody answered in time and it leaned that way, since it may be waiting", @session.permissions.sole.step_words
  end

  test "with nobody to ask, Halon decides alone, and one that cannot decide refuses the step with why" do
    session, token = open_session(place: nil)
    FirefightAi::PermissionJudge.any_instance.expects(:decide).with { |can_ask:, **| !can_ask }.raises(FirefightAi::TerminalError, "no decision")

    perform_enqueued_jobs { ask(token: token) }
    ask(token: token)

    assert_equal "Halon refused this step. #{CodeAgentPermissionService::UNDECIDED}", response.parsed_body["message"]
    assert_empty session.questions
  end

  test "a step that fails to be decided is refused rather than left waiting out the run" do
    FirefightAi::PermissionJudge.any_instance.expects(:decide).raises(RuntimeError, "broken")

    ask
    assert_raises(RuntimeError) { CodeAgentPermissionJob.perform_now(@session.permissions.sole.id) }
    ask

    assert_equal CodeAgentPermission::REPLY_REJECT, response.parsed_body["reply"]
  end

  test "an ended session asks nothing, and a request without its permission is refused" do
    post "/code_agent/permissions", params: { id: "per_1" }.to_json, headers: headers
    assert_response :unprocessable_content

    @session.close!
    ask
    assert_response :unauthorized
  end

  private

  def ask(token: @token)
    events = [ { type: "tool_use", part: { tool: "bash", state: { status: "completed", input: { command: "bundle exec rspec spec/pool_spec.rb" }, metadata: { exit: 1 } } } },
               { type: "tool_use", part: { tool: "edit", state: { status: "completed", input: { filePath: "/runs/7f3a/spec/pool_spec.rb" } } } } ].map(&:to_json)
    post "/code_agent/permissions", params: { id: "per_1", permission: CodeAgentPermission::REPEATED, patterns: [ "bash" ], metadata: REPEATED, events: events }.to_json,
                                    headers: headers(token)
  end

  def headers(token = @token) = { "Authorization" => "Bearer #{token}", "CONTENT_TYPE" => "application/json" }

  def decision(decided, reason, lean: nil) = FirefightAi::PermissionJudge::Decision.new(decision: decided, reason: reason, lean: lean)

  def open_session(place:)
    request = CodeAgent::Request.new(principal: @bob, source: AbilityGateway::SOURCE_CONVERSATION, place: place, tool_call_id: "call_1")
    CodeAgentSession.open!(workspace: @workspace, choice: FirefightAi::ModelChoice.new(model: "gpt-4o", provider: "openai"), repository: "acme/api", request: request)
  end
end
