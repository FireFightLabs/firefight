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
    stub_update_message
  end

  test "starting a run says so in the channel and remembers the thread it opened" do
    Investigation::Delivery.new(@investigation).start!

    assert_equal "1234567890.123456", @investigation.reload.thread_id
  end

  test "a question asked in Slack is posted back as Slack shows it, so nobody is notified again and nothing is escaped twice" do
    bob = workspace_memberships(:bob_workspace_one)
    run = @workspace.investigations.create!(
      trigger_source: Investigation::TRIGGER_COMMAND, triggered_by: workspace_memberships(:alice_workspace_one), max_turns: 10, max_spend_cents: 400,
      channel_id: "C0OPS", brief: Investigation::Brief.from({ Investigation::Brief::KEY_SYMPTOM => "<!here> <@#{bob.platform_user_id}> &amp; :fire:" },
                                                            source: Investigation::Brief::SOURCE_COMMAND)
    )
    Slack::WorkspaceAdapter.any_instance.expects(:post_investigation_started).with do |arguments|
      arguments[:question] == "@here @#{bob.display_name} & 🔥"
    end.returns({ message_id: "1.2", channel_id: "C0OPS" })

    Investigation::Delivery.new(run).start!
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

  test "a finished step says how it went in a word: a not found completes, a failure is an error" do
    delivery = Investigation::Delivery.new(@investigation)
    delivery.start!
    reported = []
    Slack::Client.stubs(:append_stream).with { |arguments| reported.concat(arguments[:chunks]) }.returns({ ok: true })

    delivery.step(key: "call_1", title: "Cloudflare execute", status: :done, outcome: outcome(Chat::StepOutcome::KIND_NOT_FOUND))
    delivery.step(key: "call_2", title: "Cloudflare execute", status: :done, outcome: outcome(Chat::StepOutcome::KIND_FAILED))
    delivery.step(key: "call_3", title: "Search logs", status: :done, outcome: outcome(Chat::StepOutcome::KIND_ANSWERED))

    assert_equal [ [ "complete", "Not found" ], [ "error", "Failed" ], [ "complete", nil ] ], reported.map { |chunk| chunk.values_at(:status, :output) }
  end

  test "an answer ends the steps in the thread, clears the working state, and goes to the thread and the channel with the full answer after it" do
    delivery = Investigation::Delivery.new(@investigation)
    delivery.start!
    finding = @investigation.conclude!(summary: "The 14:02 deploy did it", gaps: "logs", short: { answer_kind: Investigation::Finding::KIND_NO_CAUSE,
                                                                                                  what_is_wrong: "Checkout fails since the deploy." })
    Slack::Client.expects(:stop_stream).with { |arguments| arguments[:blocks].nil? }.returns({ ok: true, ts: "1" })
    Slack::Client.expects(:set_agent_session_status).with { |arguments| arguments[:status] == "active" }.returns({ ok: true })
    posted = []
    Slack::Client.stubs(:post_message).with { |arguments| posted << arguments }.returns({ ok: true, ts: "2", channel: @incident.channel_id })

    delivery.answered!(finding)

    short, full = posted
    assert_equal [ true, nil ], [ short[:reply_broadcast], full[:reply_broadcast] ]
    assert_equal [ "1234567890.123456" ] * 2, [ short[:thread_ts], full[:thread_ts] ]
    assert_equal "No cause found yet: Checkout fails since the deploy.", short[:text]
    assert_equal ":page_facing_up:  *The full answer*", full[:blocks].first.dig(:text, :text)
    assert_equal "2", @investigation.reload.answer_message_id
  end

  test "the message that started the run is its checklist, and the answer redraws it finished, in place" do
    started = nil
    Slack::Client.stubs(:post_message).with { |arguments| started ||= arguments }.returns({ ok: true, ts: "1234567890.123456", channel: @incident.channel_id })
    delivery = Investigation::Delivery.new(@investigation)
    delivery.start!

    plan = started[:blocks].first
    assert_equal [ "plan", "Investigating #{@incident.identifier}" ], plan.values_at(:type, :title)
    assert_equal [ [ "Gathered what Firefight knows", "complete" ], [ "Find the cause", "pending" ] ], plan[:tasks].map { |task| task.values_at(:title, :status) }

    finding = @investigation.conclude!(summary: "The 14:02 deploy did it", short: { answer_kind: Investigation::Finding::KIND_NO_CAUSE,
                                                                                   what_is_wrong: "Checkout fails since the deploy." })
    Slack::Client.expects(:update_message).with do |arguments|
      redrawn = arguments[:blocks].first
      arguments[:ts] == "1234567890.123456" && redrawn[:title] == "Investigated #{@incident.identifier}" &&
        redrawn[:tasks].last.values_at(:title, :status) == [ "No cause found yet", "complete" ]
    end.returns({ ok: true })

    delivery.answered!(finding)
  end

  test "the checklist follows the run's steps, grouped by what they read, redrawn no more often than Slack allows" do
    delivery = Investigation::Delivery.new(@investigation)
    delivery.start!
    @investigation.steps.create!(position: 1, tool_name: "search_logs", action_key: "grafana.search_logs", status: Investigation::Step::STATUS_RUNNING)
    redrawn = []
    Slack::Client.stubs(:update_message).with { |arguments| redrawn << arguments[:blocks].first }.returns({ ok: true })

    delivery.step(key: "call_1", title: "Search logs", status: :running)
    @investigation.steps.create!(position: 2, tool_name: "what_changed", action_key: "map.read", status: Investigation::Step::STATUS_SUCCEEDED)
    delivery.step(key: "call_2", title: "What changed", status: :done)

    assert_equal 1, redrawn.size
    assert_equal [ "Gathered what Firefight knows", "Read the logs and metrics", "Find the cause" ], redrawn.sole[:tasks].pluck(:title)
    assert_equal "in_progress", redrawn.sole[:tasks].second[:status]
  end

  test "a redraw Slack refuses is tried again with the same checklist, so the last one is never lost" do
    delivery = Investigation::Delivery.new(@investigation)
    delivery.start!
    Slack::Client.expects(:update_message).twice.raises(AdapterError::ServerError, "slack is down").then.returns({ ok: true })

    delivery.stopped!(Investigation::BUDGET_SPENT)
    delivery.stopped!(Investigation::BUDGET_SPENT)
  end

  test "a run that stops redraws its checklist saying so, in the thread only" do
    delivery = Investigation::Delivery.new(@investigation)
    delivery.start!
    Slack::Client.expects(:update_message).with do |arguments|
      arguments[:blocks].first[:tasks].last.values_at(:title, :status) == [ "Stopped without an answer", "error" ]
    end.returns({ ok: true })
    Slack::Client.expects(:post_message).never

    delivery.stopped!(Investigation::BUDGET_SPENT)
  end

  test "a workspace whose Slack refuses plan blocks gets the same checklist as text, remembered so it is not asked again" do
    posted = []
    Slack::Client.stubs(:post_message).with { |arguments| posted << arguments }.returns({ ok: true, ts: "1234567890.123456", channel: "C1" })
    Slack::Client.stubs(:post_message).with { |arguments| arguments[:blocks]&.first&.dig(:type) == "plan" }.raises(AdapterError::Unrenderable, "invalid_blocks")

    Investigation::Delivery.new(@investigation).start!

    assert_includes posted.last[:blocks].first.dig(:text, :text), "Investigating #{@incident.identifier}"
    assert_includes posted.last[:blocks].third.dig(:text, :text), ":white_check_mark: Gathered what Firefight knows"
    assert @workspace.reload.platform_data["plan_blocks_refused_at"].present?

    Slack::Client.expects(:update_message).with { |arguments| arguments[:blocks].first[:type] == "section" }.returns({ ok: true })
    @investigation.conclude!(summary: "No cause yet")
    Investigation::Delivery.new(@investigation.reload).send(:show_progress, Investigation::Progress.new(@investigation))
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

    Slack::Client.expects(:post_message).with { |arguments| arguments[:thread_ts].present? }.twice.returns({ ok: true, ts: "2" })

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
      arguments[:channel] == "C0GENERAL" && arguments[:blocks].first[:title] == "Investigating \"checkout is slow\""
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

  private

  def outcome(kind) = Chat::StepOutcome.new(kind: kind, said: nil, lines: [], total: 0, size: 0, link: nil)
end
