require "test_helper"

class Conversation::RecoveryTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  # Stands in for the queue, which the test database does not hold. The rest is the real recovery.
  class FakeJobs
    attr_reader :retried

    def initialize(running: false, failed: nil)
      @running = running
      @failed = failed
      @retried = []
    end

    def waiting_or_running?(_conversation) = @running

    def last_failed(_conversation, since:) = (@failed if since)

    # A job run again is back on the queue until its worker dies too.
    def retry!(failed)
      @retried << failed
      @running = true
    end

    def die! = (@running = false)
  end

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
    @conversation.ask!("What changed today?")
    @conversation.update!(answer_owed_since: 5.minutes.ago)
    @asking = @conversation.chat.add_message(role: :assistant, content: "")
  end

  test "a reply whose worker was killed before it changed anything is run again, once" do
    call!("search_incidents")
    jobs = FakeJobs.new(failed: :the_failed_job)

    Conversation::Recovery.sweep!(jobs: jobs)
    Conversation::Recovery.sweep!(jobs: jobs)

    assert_equal [ :the_failed_job ], jobs.retried
    assert @conversation.reload.answer_owed?, "the second sweep found the turn already being run again"

    # The run again was killed too, so the turn is ended rather than run a third time.
    jobs.die!
    @conversation.update!(answer_owed_since: 4.minutes.ago)
    Conversation::Recovery.sweep!(jobs: jobs)

    assert_equal [ :the_failed_job ], jobs.retried
    assert_ended
  end

  test "a reply still waiting for its turn or running is never touched" do
    call!("search_incidents")

    Conversation::Recovery.sweep!(jobs: FakeJobs.new(running: true, failed: :an_older_failure))

    assert @conversation.reload.answer_owed?
    assert_nil @conversation.chat.tool_calls.sole.result_id
    assert_not_includes @conversation.chat.readable_messages.map(&:content), Conversation::Recovery::INTERRUPTED
  end

  test "a turn that already called something that changes things is ended, never run again" do
    call!("restart")
    jobs = FakeJobs.new(failed: :the_failed_job)

    Conversation::Recovery.sweep!(jobs: jobs)

    assert_empty jobs.retried
    assert_ended
    assert_equal Chat::UnfinishedCalls::INTERRUPTED, @conversation.chat.tool_calls.sole.result.content
  end

  test "a turn whose job is gone without failing is ended, and the empty reply it left on the page is removed" do
    Conversation::Recovery.sweep!(jobs: FakeJobs.new)

    assert_ended
    assert_not Chat::Message.exists?(@asking.id)
  end

  test "a lost reply in a Slack thread is ended there, so no spinner is left" do
    thread = @workspace.conversations.create!(
      kind: Conversation::KIND_CHANNEL, channel_id: "C_INCIDENT", thread_id: "1700000000.000100",
      started_by: @member, max_turns: 10, max_spend_cents: 40
    )
    thread.ask!("What changed today?")
    thread.update!(answer_owed_since: 5.minutes.ago)
    @conversation.reply_delivered!
    stub_agent_session
    Slack::Client.expects(:post_message).with do |arguments|
      arguments[:text] == Conversation::Recovery::INTERRUPTED && arguments[:thread_ts] == "1700000000.000100"
    end.returns({ ok: true, ts: "1" })

    Conversation::Recovery.sweep!(jobs: FakeJobs.new)

    assert_not thread.reload.answer_owed?
  end

  test "the answer a lost turn was writing in its thread is ended where it stopped, so it never reads as finished" do
    thread = lost_thread_turn(shown: true)
    Slack::Client.expects(:stop_stream).with do |arguments|
      arguments[:ts] == "1700000000.000300" && arguments[:markdown_text] == "\n\n#{Conversation::Delivery::INTERRUPTED_HERE}"
    end.returns({ ok: true, ts: "1700000000.000300" })

    Conversation::Recovery.sweep!(jobs: FakeJobs.new)

    assert_nil thread.reload.answer_message_id
  end

  test "an answer a lost turn opened in its thread without showing anything is removed" do
    thread = lost_thread_turn(shown: false)
    Slack::Client.expects(:delete_message).with(has_entries(ts: "1700000000.000300")).returns({ ok: true })
    Slack::Client.expects(:stop_stream).never

    Conversation::Recovery.sweep!(jobs: FakeJobs.new)

    assert_nil thread.reload.answer_message_id
  end

  test "a question asked a moment ago, or one the page stopped waiting on, is left alone" do
    @conversation.update!(answer_owed_since: 10.seconds.ago)
    Conversation::Recovery.sweep!(jobs: FakeJobs.new)
    assert @conversation.reload.answer_owed?

    @conversation.update!(answer_owed_since: (Conversation::REPLY_CEILING + 1.minute).ago)
    Conversation::Recovery.sweep!(jobs: FakeJobs.new)
    assert_not_includes @conversation.chat.readable_messages.map(&:content), Conversation::Recovery::INTERRUPTED
  end

  private

  def lost_thread_turn(shown:)
    thread = @workspace.conversations.create!(
      kind: Conversation::KIND_CHANNEL, channel_id: "C_INCIDENT", thread_id: "1700000000.000100",
      started_by: @member, max_turns: 10, max_spend_cents: 40
    )
    thread.ask!("What changed today?")
    thread.update!(answer_owed_since: 5.minutes.ago, answer_message_id: "1700000000.000300", answer_shown: shown)
    @conversation.reply_delivered!
    Slack::Client.stubs(:set_agent_session_status).returns({ ok: true })
    Slack::Client.stubs(:post_message).returns({ ok: true, ts: "1700000000.000400" })
    thread
  end

  def call!(name)
    @asking.ruby_llm_tool_calls.create!(tool_call_id: "call_#{name}", name: name, arguments: {})
  end

  def assert_ended
    @conversation.reload
    assert_not @conversation.answer_owed?
    assert_nil @conversation.reply_recovered_at
    assert_equal Conversation::Recovery::INTERRUPTED, @conversation.chat.readable_messages.last.content
  end
end
