require "test_helper"

class Investigation::DeliveryTest < ActiveSupport::TestCase
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
end
