require "test_helper"

class Investigation::DeliveryTest < ActiveSupport::TestCase
  include ActionCable::TestHelper
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @investigation = @workspace.investigations.create!(
      subject: @incident, trigger_source: Investigation::TRIGGER_COMMAND,
      triggered_by: workspace_memberships(:alice_workspace_one), max_turns: 10, max_spend_cents: 400
    )
    stub_post_message
    stub_agent_session
  end

  test "starting a run says so in the channel and remembers the thread it opened" do
    Investigation::Delivery.new(@investigation).start!

    assert_equal "1234567890.123456", @investigation.reload.thread_id
  end

  test "the agent shows as working in the thread it opened" do
    Slack::Client.expects(:set_agent_session_status).with do |arguments|
      arguments[:status] == "processing" && arguments[:channel] == @incident.channel_id
    end.returns({ ok: true })

    Investigation::Delivery.new(@investigation).start!
  end

  test "each step is reported against the answer it belongs to" do
    delivery = Investigation::Delivery.new(@investigation)
    delivery.start!
    Slack::Client.expects(:append_stream).with do |arguments|
      arguments[:chunks].sole[:status] == "in_progress"
    end.returns({ ok: true })

    delivery.step(key: "call_1", title: "Read recent deploys", status: :running)
  end

  test "an answer is posted and the working state is cleared" do
    delivery = Investigation::Delivery.new(@investigation)
    delivery.start!
    finding = @investigation.conclude!(summary: "The 14:02 deploy did it", gaps: "logs")
    Slack::Client.expects(:stop_stream).with { |arguments| arguments[:blocks].present? }.returns({ ok: true, ts: "1" })
    Slack::Client.expects(:set_agent_session_status).with { |arguments| arguments[:status] == "active" }.returns({ ok: true })

    delivery.answered!(finding)
  end

  test "the charts a run drew are posted in its thread after the answer" do
    delivery = Investigation::Delivery.new(@investigation)
    delivery.start!
    chat = @workspace.chats.create!(owner: @investigation, model: "claude-sonnet-4-5", provider: :anthropic)
    Chat::Chart.record!(chat, "call_1", [ { "title" => "5xx responses of web", "unit" => "count", "from" => "2026-09-25T14:00:00Z",
                                             "to" => "2026-09-25T15:00:00Z", "series" => [ { "label" => "web-1", "points" => [ [ "2026-09-25T14:05:00Z", 42 ] ] } ] } ])
    finding = @investigation.conclude!(summary: "The 14:02 deploy did it", gaps: "logs")
    Slack::Client.stubs(:stop_stream).returns({ ok: true, ts: "1" })
    Slack::Client.expects(:upload_file).with { |arguments| arguments[:title] == "5xx responses of web" && arguments[:thread_ts] == @investigation.reload.thread_id }.returns({ ok: true })

    delivery.answered!(finding)
  end

  test "an answer that reaches the thread is recorded as posted, so an operator can find one that did not" do
    delivery = Investigation::Delivery.new(@investigation)
    delivery.start!
    finding = @investigation.conclude!(summary: "The 14:02 deploy did it", gaps: "logs")
    Slack::Client.stubs(:stop_stream).returns({ ok: true, ts: "1" })

    delivery.answered!(finding)

    assert @investigation.reload.answer_posted_at
  end

  test "an answer whose post fails is not recorded as posted" do
    delivery = Investigation::Delivery.new(@investigation)
    delivery.start!
    finding = @investigation.conclude!(summary: "The 14:02 deploy did it", gaps: "logs")
    Slack::WorkspaceAdapter.any_instance.stubs(:post_investigation_answer).raises(AdapterError::ServerError, "ratelimited")

    assert_raises(AdapterError::ServerError) { delivery.answered!(finding) }
    assert_nil @investigation.reload.answer_posted_at
  end

  test "a run that stops without an answer says why" do
    delivery = Investigation::Delivery.new(@investigation)
    delivery.start!

    Slack::Client.expects(:stop_stream).with do |arguments|
      arguments[:blocks].first.dig(:text, :text).include?("Budget spent")
    end.returns({ ok: true, ts: "1" })

    delivery.stopped!("Budget spent before it could answer")
  end

  test "a workspace without the agent features still gets the answer" do
    Slack::Client.stubs(:start_stream).raises(AdapterError, "unknown_method")
    delivery = Investigation::Delivery.new(@investigation)
    delivery.start!
    finding = @investigation.conclude!(summary: "The 14:02 deploy did it")

    Slack::Client.expects(:post_message).with { |arguments| arguments[:thread_ts].present? }.returns({ ok: true, ts: "2" })

    delivery.answered!(finding)
  end

  test "a resumed run picks its thread back up rather than announcing itself twice" do
    delivery = Investigation::Delivery.new(@investigation)
    delivery.start!
    Slack::Client.expects(:post_message).never

    Investigation::Delivery.new(@investigation.reload).start!

    assert_equal "1234567890.123456", @investigation.reload.thread_id
  end

  test "an investigation with no channel says nothing" do
    @incident.update!(channel_id: nil)
    Slack::Client.expects(:post_message).never

    Investigation::Delivery.new(@investigation).start!
  end

  test "a question asked in a channel is announced there by its own words" do
    question = question_run(channel_id: "C0GENERAL")
    Slack::Client.expects(:post_message).with do |arguments|
      arguments[:channel] == "C0GENERAL" && arguments[:blocks].first.dig(:text, :text).include?("checkout is slow")
    end.returns({ ok: true, ts: "1234567890.123456" })

    Investigation::Delivery.new(question).start!

    assert_equal "C0GENERAL", question.reload.channel_id
  end

  test "a question asked where Firefight cannot post is answered to whoever asked, directly" do
    question = question_run(channel_id: "C0PRIVATE")
    alice = workspace_memberships(:alice_workspace_one)
    Slack::Client.stubs(:post_message).with { |arguments| arguments[:channel] == "C0PRIVATE" }.raises(AdapterError::NotInChannel, "not_in_channel")
    Slack::Client.expects(:post_message).with { |arguments| arguments[:channel] == alice.platform_user_id }
                 .returns({ ok: true, ts: "1234567890.123456", channel: "D0ALICE" })

    Investigation::Delivery.new(question).start!

    assert_equal "D0ALICE", question.reload.channel_id
  end

  test "a run a chat started tells the chat each time it moves" do
    conversation = @workspace.conversations.create!(
      kind: Conversation::KIND_PERSONAL, started_by: workspace_memberships(:alice_workspace_one), max_turns: 10, max_spend_cents: 50
    )
    question = question_run(conversation: conversation)

    assert_broadcasts(ConversationChannel.broadcasting_for(conversation), 2) do
      delivery = Investigation::Delivery.new(question)
      delivery.start!
      delivery.stopped!(Investigation::BUDGET_SPENT)
    end
  end

  private

  def question_run(**answer_in)
    @workspace.investigations.create!(
      trigger_source: Investigation::TRIGGER_COMMAND, triggered_by: workspace_memberships(:alice_workspace_one),
      max_turns: 10, max_spend_cents: 400, brief: { Investigation::Brief::KEY_SYMPTOM => "checkout is slow" }, **answer_in
    )
  end
end
