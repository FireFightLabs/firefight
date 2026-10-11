require "test_helper"

class Events::DirectMessageHandlerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  DM = "D0ALICE".freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    Slack::Client.stubs(:add_reaction).returns({ ok: true })
  end

  test "a direct message goes to the handler for direct messages, never to an incident channel's transcript" do
    incident = incidents(:active_critical_ws1)
    incident.update_columns(channel_id: DM)

    assert_no_difference -> { IncidentTranscriptMessage.count } do
      assert_enqueued_with(job: ConversationReplyJob) { write("what is going on", ts: "1700000000.000100") }
    end
  end

  test "a direct message starts a chat of the person's own, asked as them and answered in the thread it starts" do
    Slack::Client.expects(:add_reaction).with { |arguments| arguments[:channel] == DM && arguments[:timestamp] == "1700000000.000100" }.returns({ ok: true })

    write("what is going on", ts: "1700000000.000100")

    chat = @workspace.conversations.sole
    assert_equal Conversation::KIND_DIRECT, chat.kind
    assert_equal @alice, chat.started_by
    assert_nil chat.subject
    assert_equal [ DM, "1700000000.000100" ], [ chat.channel_id, chat.thread_id ]
    assert_equal "what is going on", chat.chat.messages.find_by!(role: Chat::Message::ROLE_USER).content
    assert_enqueued_with(job: ConversationReplyJob, args: [ chat.id, @alice.id ])
  end

  test "a new message carries on the same chat and answers in its own thread" do
    write("what is going on", ts: "1700000000.000100")
    answered
    write("and who is leading", ts: "1700000000.000200")

    chat = @workspace.conversations.sole
    assert_equal "1700000000.000200", chat.thread_id
    assert_equal %w[1700000000.000100 1700000000.000200], chat.thread_links.order(:thread_id).pluck(:thread_id)
  end

  test "a new message after a day without a word starts a new chat" do
    write("what is going on", ts: "1700000000.000100")
    answered
    old = @workspace.conversations.sole
    old.update_columns(updated_at: (Conversation::DIRECT_QUIET_AFTER + 1.minute).ago)

    write("is billing slow", ts: "1700000000.000200")

    assert_equal 2, @workspace.conversations.count
    assert_equal "1700000000.000100", old.reload.thread_id
  end

  test "a new message while Halon is still answering joins that answer, which stays in its thread" do
    write("what is going on", ts: "1700000000.000100")
    chat = @workspace.conversations.sole
    chat.update_columns(updated_at: 2.days.ago)

    write("and the database?", ts: "1700000000.000200")

    assert_equal 1, @workspace.conversations.count
    assert_equal "1700000000.000100", chat.reload.thread_id
    assert_equal [ "and the database?" ], chat.chat.queued_messages.map(&:content)
  end

  test "an archived chat is not carried on" do
    write("what is going on", ts: "1700000000.000100")
    answered
    @workspace.conversations.sole.update_columns(archived_at: Time.current)

    write("is billing slow", ts: "1700000000.000200")

    assert_equal 2, @workspace.conversations.count
  end

  test "a reply in an earlier thread carries on that thread's chat and answers there, even once it has gone quiet" do
    write("what is going on", ts: "1700000000.000100")
    answered
    write("and who is leading", ts: "1700000000.000200")
    answered
    chat = @workspace.conversations.sole
    chat.update_columns(updated_at: 3.days.ago)

    write("back to the first one", ts: "1700000000.000300", thread: "1700000000.000100")

    assert_equal 1, @workspace.conversations.count
    assert_equal "1700000000.000100", chat.reload.thread_id
  end

  test "a reply in a thread the person started earlier, before Halon answered there, carries on their chat" do
    Slack::Client.stubs(:get_message).returns({ "ts" => "1690000000.000100", "user" => @alice.platform_user_id, "text" => "hello?" })

    write("still there?", ts: "1700000000.000300", thread: "1690000000.000100")

    assert_equal "1690000000.000100", @workspace.conversations.sole.thread_id
  end

  test "a reply in a thread whose start cannot be read is answered rather than dropped" do
    Slack::Client.stubs(:get_message).raises(AdapterError, "missing_scope")

    assert_enqueued_with(job: ConversationReplyJob) { write("still there?", ts: "1700000000.000300", thread: "1690000000.000100") }
  end

  test "a reply to a message Halon sent on its own is not taken as a new chat, and the person is told how to ask" do
    Slack::Client.stubs(:get_message).returns({ "ts" => "1690000000.000100", "bot_id" => "B0FIREFIGHT", "text" => "Watch finished" })
    Slack::Client.expects(:post_message).with do |arguments|
      arguments[:channel] == DM && arguments[:thread_ts] == "1690000000.000100" && arguments[:text] == Conversation::DirectMessages::NOT_FOLLOWED
    end.returns({ ok: true, ts: "1" })
    Slack::Client.expects(:add_reaction).never

    assert_no_enqueued_jobs(only: ConversationReplyJob) { write("thanks, is it healthy now?", ts: "1700000000.000300", thread: "1690000000.000100") }
    assert_equal 0, @workspace.conversations.count
  end

  test "a reply in a running investigation's thread is added to the run as a note, and opens no chat" do
    run = investigation(status: Investigation::STATUS_RUNNING)

    assert_no_enqueued_jobs(only: ConversationReplyJob) { write("skip GitHub, look at 5xx on web", ts: "1700000000.000950", thread: run.thread_id) }

    assert_equal "skip GitHub, look at 5xx on web", run.notes.sole.content
    assert_equal @alice, run.notes.sole.sender
    assert_equal 0, @workspace.conversations.count
  end

  test "a reply in a finished investigation's thread is a chat of its own about the run's incident" do
    run = investigation(status: Investigation::STATUS_SUCCEEDED)

    write("why the pool size?", ts: "1700000000.000950", thread: run.thread_id)

    chat = @workspace.conversations.sole
    assert_equal [ Conversation::KIND_DIRECT, run.thread_id, run.subject ], [ chat.kind, chat.thread_id, chat.subject ]
  end

  test "a new chat opened in the app's agent view is a chat of its own, even while another is going" do
    write("what is going on", ts: "1700000000.000100")
    Slack::Client.stubs(:get_message).returns({ "ts" => "1700000000.000500", "subtype" => "assistant_app_thread", "bot_id" => "B0FIREFIGHT" })

    write("new question", ts: "1700000000.000600", thread: "1700000000.000500")

    assert_equal 2, @workspace.conversations.count
    assert_equal "1700000000.000500", @workspace.conversations.order(:created_at).last.thread_id
  end

  test "Halon's own messages, other apps' messages and edits are ignored" do
    write("Here is what I found", ts: "1700000000.000100", bot_id: "B0FIREFIGHT")
    write("from another app", ts: "1700000000.000200", app_id: "A0OTHER")
    write("edited", ts: "1700000000.000300", subtype: Identifiers::MESSAGE_SUBTYPE_MESSAGE_CHANGED)
    write("gone", ts: "1700000000.000400", subtype: Identifiers::MESSAGE_SUBTYPE_MESSAGE_DELETED)

    assert_equal 0, @workspace.conversations.count
    assert_no_enqueued_jobs(only: ConversationReplyJob)
  end

  test "someone from another organisation is told Halon only answers people in this workspace" do
    Slack::Client.expects(:post_message).with { |arguments| arguments[:text] == Events::DirectMessageHandler::NOT_A_MEMBER }.returns({ ok: true, ts: "1" })

    write("hello", ts: "1700000000.000100", user_team: "T0ELSEWHERE")

    assert_equal 0, @workspace.conversations.count
  end

  test "someone whose account cannot be read is told so and asks nothing" do
    Slack::Client.stubs(:get_user_info).raises(AdapterError, "user_not_found")
    Slack::Client.expects(:post_message).with { |arguments| arguments[:text] == AuthorizedDispatch::UNRESOLVED_MESSAGE }.returns({ ok: true, ts: "1" })

    write("hello", ts: "1700000000.000100", user: "U0STRANGER")

    assert_equal 0, @workspace.conversations.count
  end

  test "a person refused asking is told why in the thread they wrote in" do
    AbilityGateway.stubs(:authorize!).raises(AbilityGateway::Denied.new(Ability::Action::INVESTIGATIONS_CREATE))
    refusal = AuthorizedDispatch.denied_message(AbilityGateway::Denied.new(Ability::Action::INVESTIGATIONS_CREATE))
    Slack::Client.expects(:post_message).with { |arguments| arguments[:text] == refusal && arguments[:thread_ts] == "1700000000.000100" }.returns({ ok: true, ts: "1" })

    assert_no_enqueued_jobs(only: ConversationReplyJob) { write("what is going on", ts: "1700000000.000100") }
  end

  test "a direct message is told setup is not finished when the model's window is not known" do
    FirefightAi.stubs(:context_window).returns(nil)
    Slack::Client.expects(:post_message).with { |arguments| arguments[:text].include?("not fully set up") }.returns({ ok: true, ts: "1" })

    assert_no_enqueued_jobs(only: ConversationReplyJob) { write("what is going on", ts: "1700000000.000100") }
  end

  private

  # The turn the last message asked for has ended.
  def answered = @workspace.conversations.find_each(&:reply_delivered!)

  def write(text, ts:, thread: nil, user: @alice.platform_user_id, **extra)
    EventDispatcher.dispatch(Platforms::SLACK, {
      "team_id" => @workspace.platform_id,
      "event" => {
        "type" => Identifiers::EVENT_MESSAGE, "channel_type" => Identifiers::CHANNEL_TYPE_DIRECT, "channel" => DM,
        "user" => user, "ts" => ts, "thread_ts" => thread, "text" => text
      }.merge(extra.transform_keys(&:to_s)).compact
    })
  end

  def investigation(status:)
    @workspace.investigations.create!(
      subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_COMMAND, triggered_by: @alice,
      max_turns: 10, max_spend_cents: 400, thread_id: "1700000000.000900", channel_id: DM, status: status
    )
  end
end
