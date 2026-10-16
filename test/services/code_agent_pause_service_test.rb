require "test_helper"

# A code change paused at its spending limit is told where it came from, and only the person it runs as continues or
# stops it, from the step or from Slack.
class CodeAgentPauseServiceTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include FixPlanTestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @conversation = @workspace.conversations.create!(kind: Conversation::KIND_CHANNEL, started_by: @bob, channel_id: "C9", thread_id: "5.5",
                                                     max_turns: 5, max_spend_cents: 100)
    request = CodeAgent::Request.new(principal: @bob, source: AbilityGateway::SOURCE_CONVERSATION, place: @conversation, tool_call_id: "call_1")
    session, = CodeAgentSession.open!(workspace: @workspace, choice: FirefightAi::ModelChoice.new(model: "gpt-4o", provider: "openai"),
                                      repository: "acme/api", request: request)
    @pause = CodeAgentSession::Pause.create!(
      session: session, workspace: @workspace, conversation: @conversation, arguments: { "repo" => "acme/api", "title" => "Fix", "brief" => "Fix it" },
      repository: "acme/api", base: "main", saved_branch: "halon/fix-1a2b", saved_commit: "s" * 40, copy_ref: "c" * 40,
      agent_session_id: "ses_abc", box_key: "chat-1", budget_micros: 2_000_000, resumable_until: 15.minutes.from_now
    )
    work = Chat::CodeFixProgress.start
    work.paused!(@pause.to_h)
    Chat::StepProgress.keep!(@conversation.chat_record, "call_1", work, since: 1.hour.ago)
    @adapter = stub(post_code_pause: { channel_id: "C9", message_id: "5.7" }, update_code_pause: { success: true })
    WorkspaceAdapter.stubs(:for).returns(@adapter)
  end

  test "the pause is posted in the chat's thread with Continue and Stop, saying what was saved and that only the asker decides" do
    @adapter.expects(:post_code_pause).with(channel_id: "C9", thread_id: "5.5", pause: @pause).returns(channel_id: "C9", message_id: "5.7")
    CodeAgentPauseService.tell!(@pause)
    assert_equal [ "C9", "5.7" ], @pause.reload.values_at(:message_channel_id, :message_id)

    blocks = Slack::Messages::CodePause.build(@pause)
    texts = blocks.flat_map { |block| [ block.dig(:text, :text), *Array(block[:elements]).map { |element| element[:text].is_a?(Hash) ? element[:text][:text] : element[:text] } ] }.compact
    assert_includes texts, "This fix has reached its spending limit before finishing. Continue?"
    assert_includes texts, "Its work so far is saved on `halon/fix-1a2b`."
    assert_includes texts, "Only <@#{@bob.platform_user_id}> can decide."
    buttons = blocks.find { |block| block[:type] == "actions" }[:elements]
    assert_equal [ [ "Continue", Identifiers::CODE_PAUSE_CONTINUE, "primary" ], [ "Stop", Identifiers::CODE_PAUSE_STOP, nil ] ],
                 buttons.map { |button| [ button.dig(:text, :text), button[:action_id], button[:style] ] }
    assert(texts.none? { |text| text.include?("$") || text.include?("—") || text.include?(";") }, "no dollars and no dashes")
  end

  test "a decided pause stays on its own call when a later call reused the id before anyone decided" do
    travel 1.minute
    later = Chat::CodeFixProgress.start
    later.add("A later change")
    Chat::StepProgress.keep!(@conversation.chat_record, "call_1", later, since: Time.current)
    @pause.update_columns(status: CodeAgentSession::Pause::STATUS_CONTINUING)

    CodeAgentPauseService.keep_on_step!(@pause.reload)

    first, second = @conversation.chat_record.step_progresses.where(tool_call_id: "call_1").order(:created_at).map(&:work)
    assert_equal CodeAgentSession::Pause::STATUS_CONTINUING, first.pause["status"]
    assert_nil second.pause
  end

  test "a decided pause is kept on its call's work even when the call reported work before the change was opened" do
    chat = @conversation.chat_record
    chat.step_progresses.delete_all
    travel_to 10.minutes.ago do
      chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "").ruby_llm_tool_calls.create!(tool_call_id: "call_1", name: "fix_code", arguments: {})
    end
    early = travel_to(9.minutes.ago) { Chat::StepProgress.keep!(chat, "call_1", Chat::CodeFixProgress.start, since: 1.hour.ago) }
    @pause.session.update_columns(created_at: 8.minutes.ago)
    travel 1.minute
    chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "").ruby_llm_tool_calls.create!(tool_call_id: "call_1", name: "fix_code", arguments: {})
    later = Chat::StepProgress.keep!(chat, "call_1", Chat::CodeFixProgress.start, since: Time.current)
    @pause.update_columns(status: CodeAgentSession::Pause::STATUS_CONTINUING)

    CodeAgentPauseService.keep_on_step!(@pause.reload)

    assert_equal CodeAgentSession::Pause::STATUS_CONTINUING, early.reload.work.pause["status"]
    assert_nil later.reload.work.pause
  end

  test "Continue from the dashboard carries the change on in a turn as the person, and anyone else is told who can decide" do
    sign_in(@alice.user, @workspace)
    post code_agent_pause_continue_path(@pause)
    assert_equal "Only Bob Jones can decide, since the change runs as them.", flash[:alert]
    assert @pause.reload.offered?

    sign_in(@bob.user, @workspace)
    assert_enqueued_with(job: ConversationReplyJob, args: [ @conversation.id, @bob.id, nil, nil, nil, @pause.id ]) do
      post code_agent_pause_continue_path(@pause)
    end
    assert_equal "The change carries on.", flash[:notice]
    assert @pause.reload.continuing?
    assert_equal CodeAgentSession::Pause::STATUS_CONTINUING, @conversation.chat_record.step_progresses.find_by!(tool_call_id: "call_1").work.pause["status"],
                 "the step shows it was continued"
    assert_equal "This was already decided.", CodeAgentPauseService.stop!(@pause, by: @bob)
  end

  test "Stop from Slack deletes the saved work through the code host and redraws the message" do
    @pause.update_columns(message_channel_id: "C9", message_id: "5.7")
    @adapter.expects(:update_code_pause).with { |pause:, **| pause.stopped? }.returns(success: true)
    pack = mock("pack")
    Integrations::NativePack.stubs(:fetch!).returns(pack)
    pack.expects(:discard_pause!).with { |_row, pause| pause.id == @pause.id }
    @pause.session.update_columns(integration_environment_id: integration_row.id)

    Interactions::CodePauseDecisionHandler.execute(
      Interaction.new(platform: Platforms::SLACK, type: Interaction::BLOCK_ACTIONS, team_id: @workspace.platform_id, channel_id: "C9",
                      user_id: @bob.platform_user_id, action_id: Identifiers::CODE_PAUSE_STOP, action_value: @pause.id)
    )

    assert @pause.reload.stopped?
    blocks = Slack::Messages::CodePause.build(@pause)
    assert_equal "*Bob Jones* chose Stop, so the saved work was deleted.", blocks.last[:elements].sole[:text]
    assert_not blocks.any? { |block| block.dig(:elements, 0, :text).to_s.include?("is saved on") }, "a stopped change no longer says its work is saved"

    @pause.update_columns(saved_branch: nil)
    assert_equal "*Bob Jones* chose Stop.", Slack::Messages::CodePause.build(@pause).last[:elements].sole[:text]
  end

  test "a turn started by Continue runs the change through the person's own tool with the pause named" do
    row = integration_row
    @pause.session.update_columns(integration_environment_id: row.id)
    @pause.update_columns(status: CodeAgentSession::Pause::STATUS_CONTINUING)
    turn = Conversation::Turn.new(@conversation, asker: @bob)
    Chat::Tools::Connection.any_instance.expects(:run).with do |arguments, **|
      arguments == { "repo" => "acme/api", "title" => "Fix", "brief" => "Fix it", CodeAgentSession::Pause::CONTINUE_ARG => @pause.id }
    end.returns("Opened https://github.com/acme/api/pull/9.")

    said = CodeAgentPauseService.run_continue!(turn, @pause)

    assert_equal "Opened https://github.com/acme/api/pull/9.", said
    assert_match "The person pressed Continue on the code change in acme/api", CodeAgentPauseService.continued_note(@pause, said)
  end

  test "a turn started by Continue carries the change on as a step of its own, saved and shown working before it runs, with its progress" do
    @pause.session.update_columns(integration_environment_id: integration_row.id)
    conversation = Conversation.start_personal!(workspace: @workspace, member: @bob)
    @pause.update_columns(status: CodeAgentSession::Pause::STATUS_CONTINUING, conversation_id: conversation.id)
    @pause.session.update_columns(place_id: conversation.id)
    chat = conversation.chat_record
    runner = Conversation::Runner.new(conversation, asker: @bob, code_pause: @pause.reload)
    told = []
    ConversationChannel.stubs(:broadcast_to).with { |_conversation, event| told << event }
    work = Chat::CodeFixProgress.start
    work.add("Carrying on from halon/fix-1a2b")
    seen_before = nil
    Chat::Tools::Connection.any_instance.expects(:run).with do |arguments, tool_call_id:, **|
      call = chat.tool_calls.find_by(tool_call_id: tool_call_id)
      seen_before = [ call&.name, call&.arguments, call&.result_id, told.map { |event| event[:type] } ]
      runner.instance_variable_get(:@turn).progress_listener(tool_call_id).call(work)
      arguments[CodeAgentSession::Pause::CONTINUE_ARG] == @pause.id
    end.returns("Opened https://github.com/acme/api/pull/9.")

    runner.send(:run_code_pause, chat)

    call = chat.tool_calls.sole
    assert_equal [ "github_fix_code", CodeAgentPauseService.continue_arguments(@pause), nil ], seen_before.first(3), "the step is saved before the change runs"
    assert_equal [ Conversation::LiveDelivery::EVENT_THINKING, Conversation::LiveDelivery::EVENT_STEP ], seen_before.last.uniq.first(2),
                 "the page is told the turn started and shown the step before the change runs"
    assert_equal "Opened https://github.com/acme/api/pull/9.", call.reload.result.content
    assert_equal [ "Carrying on from halon/fix-1a2b" ], chat.step_progresses.find_by!(tool_call_id: call.tool_call_id).work.lines.map(&:text),
                 "its progress is kept under the step, so a reload shows it"
    assert told.any? { |event| event[:type] == Conversation::LiveDelivery::EVENT_STEP && event[:key] == call.tool_call_id && event[:progress].present? }
    assert_match "The person pressed Continue on the code change in acme/api", chat.messages.where(nudge: true).order(:created_at).last.content
    assert_equal [ Chat::Message::ROLE_USER, Chat::Message::ROLE_ASSISTANT, Chat::Message::ROLE_TOOL ],
                 chat.messages.order(:created_at).last(3).map(&:role), "the note comes before the call, never between the call and its answer"
  end

  test "a fix's pause with no thread is asked in a direct message, and Continue there carries the change on under that message" do
    pause = step_pause
    pause.session.place.plan.finding.investigation.update_columns(thread_id: nil)
    @adapter.expects(:post_code_pause_to_user).with(user_id: @bob.platform_user_id, pause: pause).returns(channel_id: "D7", message_id: "8.1")
    CodeAgentPauseService.tell!(pause)
    assert_equal [ "D7", "8.1" ], pause.reload.values_at(:message_channel_id, :message_id)

    assert_enqueued_jobs(1, only: ConversationReplyJob) { assert_nil CodeAgentPauseService.continue!(pause, by: @bob) }

    conversation = @workspace.conversations.find_by!(channel_id: "D7", thread_id: "8.1")
    assert_equal conversation, pause.reload.conversation
    assert pause.continuing?
  end

  test "a Continue with nowhere to carry the change on leaves Continue and Stop to choose from" do
    pause = step_pause
    pause.session.place.plan.finding.investigation.update_columns(thread_id: nil)

    assert_equal CodeAgentPauseService::COULD_NOT_CONTINUE, CodeAgentPauseService.continue!(pause, by: @bob)

    assert pause.reload.offered?
    assert_nil CodeAgentPauseService.stop!(pause, by: @bob), "Stop still works"
  end

  test "a Continue that fails before carrying the change on offers the choice again, and one that carried it on never does" do
    @pause.session.update_columns(integration_environment_id: integration_row.id)
    @pause.update_columns(status: CodeAgentSession::Pause::STATUS_CONTINUING, decided_by_id: @bob.id, decided_at: Time.current)
    Chat::Tools::Connection.any_instance.stubs(:run).raises(ActiveRecord::ConnectionTimeoutError)

    assert_equal CodeAgentPauseService::COULD_NOT_CONTINUE, CodeAgentPauseService.run_continue!(Conversation::Turn.new(@conversation, asker: @bob), @pause)
    assert @pause.reload.offered?
    assert_nil @pause.decided_by_id

    @pause.update_columns(status: CodeAgentSession::Pause::STATUS_CONTINUING, resumed_at: Time.current)
    CodeAgentPauseService.run_continue!(Conversation::Turn.new(@conversation, asker: @bob), @pause)
    assert @pause.reload.continuing?
  end

  test "Stop says the saved branch may still be there when the code host would not delete it, and closes the box either way" do
    row = integration_row
    @pause.session.update_columns(integration_environment_id: row.id)
    CodeBox.create!(workspace: @workspace, key: "chat-1", address: "http://box", box_ref: "box-1", provider: "docker", secret: "s", last_used_at: Time.current)
    Integrations::GithubApp.stubs(:installation_token).returns("ghs_token")
    Integrations::GithubApp.expects(:write).with(:delete, "/repos/acme/api/git/refs/heads/halon/fix-1a2b", token: "ghs_token")
                           .raises(Integrations::GithubApp::Error, "GitHub answered 500")

    assert_equal CodeAgentPauseService::COULD_NOT_STOP, CodeAgentPauseService.stop!(@pause, by: @bob)

    assert @pause.reload.stopped?
    assert_not CodeBox.live.exists?(key: "chat-1")
  end

  test "Stop closes the box of a change whose code host connection is gone" do
    CodeBox.create!(workspace: @workspace, key: "chat-1", address: "http://box", box_ref: "box-1", provider: "docker", secret: "s", last_used_at: Time.current)

    assert_nil CodeAgentPauseService.stop!(@pause, by: @bob)
    assert_not CodeBox.live.exists?(key: "chat-1")
  end

  private

  # A pause from a fix's step, which has no chat of its own.
  def step_pause
    step = build_fix_plan(@workspace).steps.third
    request = CodeAgent::Request.new(principal: @bob, source: AbilityGateway::SOURCE_WEB, place: step)
    session, = CodeAgentSession.open!(workspace: @workspace, choice: FirefightAi::ModelChoice.new(model: "gpt-4o", provider: "openai"),
                                      repository: "acme/api", request: request)
    CodeAgentSession::Pause.create!(
      session: session, workspace: @workspace, arguments: { "repo" => "acme/api", "title" => "Fix", "brief" => "Fix it" }, repository: "acme/api",
      base: "main", saved_branch: "halon/fix-1a2b", saved_commit: "s" * 40, copy_ref: "c" * 40, budget_micros: 2_000_000, resumable_until: 15.minutes.from_now
    )
  end

  def integration_row
    github = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub", slug: "github")
    github.tools.create!(name: "fix_code", description: "Writes code", params_schema: {}, enabled: true, read_only: false)
    github.integration_environments.create!(base_config: { "installation_id" => "1" })
  end
end
