require "test_helper"

class Conversation::DeliveryTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    limits = @workspace.conversation_limits
    @conversation = @workspace.conversations.create!(
      kind: Conversation::KIND_CHANNEL, channel_id: "C1", thread_id: "1.2", max_turns: limits.max_turns, max_spend_cents: limits.max_spend_cents
    )
    @chat = @workspace.chats.create!(owner: @conversation, model: "claude-sonnet-4-5", provider: :anthropic)
    Chat::Chart.record!(@chat, "call_7", [ { "title" => "CPU of web", "unit" => "vCPU", "from" => "2026-09-25T14:00:00Z", "to" => "2026-09-25T15:00:00Z",
                                             "summary" => "web-1: max 0.8", "series" => [ { "label" => "web-1", "points" => [ [ "2026-09-25T14:05:00Z", 0.8 ] ] } ] } ])
    @adapter = Slack::WorkspaceAdapter.new(@workspace)
    WorkspaceAdapter.stubs(:for).returns(@adapter)
    @adapter.stubs(:post_agent_reply).returns({ message_id: "1.3", channel_id: "C1" })
  end

  test "the charts of a step that drew them are posted in the thread after the answer, drawn as images" do
    delivery = Conversation::Delivery.for(@conversation)
    @adapter.stubs(:report_agent_step)
    delivery.step(key: "call_7", step: Chat::Tools::Step.new(title: "Query metrics", headline: "", asked: [], card: Chat::Tools.chart_card),
                  status: FirefightAi::AgentLoop::STEP_DONE)
    @adapter.expects(:post_charts).with do |channel_id:, thread_id:, charts:|
      channel_id == "C1" && thread_id == "1.2" && charts.sole.title == "CPU of web" && charts.sole.png.start_with?("\x89PNG".b)
    end.returns([])

    delivery.answered!("CPU peaked at 0.8.")
  end

  test "a thread never shows a chart's marker, streamed in pieces or posted whole, and the chart still follows the answer" do
    marker = "{{chart:#{@chat.charts.sole.handle}}}"
    @adapter.stubs(:start_agent_answer).returns({ answer_id: "1.25" })
    delivery = Conversation::Delivery.for(@conversation)
    delivery.thinking!
    appended = +""
    @adapter.stubs(:append_agent_text).with { |text:, **| appended << text }.returns({ streaming: true })
    @adapter.stubs(:report_agent_step)
    delivery.step(key: "call_7", step: Chat::Tools::Step.new(title: "Query metrics", headline: "", asked: [], card: Chat::Tools.chart_card),
                  status: FirefightAi::AgentLoop::STEP_DONE)
    @adapter.expects(:post_agent_reply).with { |text:, **| text == "CPU peaked at 0.8.\n\nIt fell back after." }.returns({ message_id: "1.3", channel_id: "C1" })
    @adapter.expects(:post_charts).returns([])

    [ "CPU peaked at 0.8.\n\n#{marker[0, 5]}", "#{marker[5..]}\n\nIt fell ", "back after." ].each { |piece| delivery.chunk(piece) }
    delivery.answered!("CPU peaked at 0.8.\n\n#{marker}\n\nIt fell back after.")

    assert_equal "CPU peaked at 0.8.\n\nIt fell back after.", appended
  end

  test "the pages Halon's browser saw are posted under the answer, and before a send it asks about, never twice" do
    Chat::Screenshot.record!(@chat, [ { "name" => "desktop", "final_url" => "https://shop.example.com", "title" => "Shop",
                                        "screenshot" => Base64.strict_encode64("\xFF\xD8\xFFjpeg".b) } ], tool_call_id: "call_8")
    delivery = Conversation::Delivery.for(@conversation)
    @adapter.stubs(:report_agent_step)
    delivery.step(key: "call_8", step: Chat::Tools.step(Chat::Tools::Browser::NAME, { "url" => "https://shop.example.com" }), status: FirefightAi::AgentLoop::STEP_DONE)
    @adapter.expects(:post_screenshots).with do |screenshots:, left_out:, **|
      screenshots.sole.caption == "Desktop: Shop at https://shop.example.com" && screenshots.sole.jpeg == "\xFF\xD8\xFFjpeg".b && left_out.zero?
    end.returns([]).once
    @adapter.stubs(:ask_agent_confirmation).returns({ message_id: "1.9" })

    delivery.confirm!([])
    delivery.answered!("Checkout loads.")
  end

  test "an answer whose steps drew nothing posts no charts" do
    @adapter.expects(:post_charts).never

    Conversation::Delivery.for(@conversation).answered!("Nothing to chart.")
  end

  test "past the limit, the charts left out are counted in a note rather than dropped quietly" do
    extra = Chat::Chart::POSTED_LIMIT + 2
    extra.times { |index| Chat::Chart.record!(@chat, "call_9", [ { "title" => "Chart #{index}", "from" => "2026-09-25T14:00:00Z", "to" => "2026-09-25T15:00:00Z", "series" => [] } ]) }

    Chat::Chart.posted_under_answer(@chat.charts.where(tool_call_id: "call_9")) do |posts|
      assert_equal Chat::Chart::POSTED_LIMIT + 1, posts.size
      assert_equal "2 more charts", posts.last.title
      assert_nil posts.last.png
    end
  end

  test "once the answer is in, each message Halon was working on loses its eyes and gets a check, once" do
    @conversation.acknowledged!("1.21")
    @conversation.acknowledged!("1.22")
    marked = []
    Slack::Client.stubs(:remove_reaction).with { |arguments| marked << [ :removed, arguments[:timestamp], arguments[:name] ] }.returns({ ok: true })
    Slack::Client.stubs(:add_reaction).with { |arguments| marked << [ :added, arguments[:timestamp], arguments[:name] ] }.returns({ ok: true })

    Conversation::Delivery.for(@conversation).answered!("Done.")
    Conversation::Delivery.for(@conversation).answered!("Done again.")

    assert_equal [ [ :removed, "1.21", "eyes" ], [ :added, "1.21", "heavy_check_mark" ], [ :removed, "1.22", "eyes" ], [ :added, "1.22", "heavy_check_mark" ] ], marked
    assert_empty @conversation.reload.acknowledged_message_ids
  end

  test "a reaction Slack will not take off never stops the answer" do
    @conversation.acknowledged!("1.21")
    Slack::Client.stubs(:remove_reaction).raises(AdapterError.new("no_reaction"))
    Slack::Client.expects(:add_reaction).returns({ ok: true })

    assert_nothing_raised { Conversation::Delivery.for(@conversation).answered!("Done.") }
  end

  test "a step line in the thread names what kind of system it read, never the tool or its connection" do
    @adapter.expects(:report_agent_step).with { |title:, **| title == "Read the code" }
    step = Chat::Tools::Step.new(title: "Github fix code · acme", headline: "", asked: [], card: nil, line: "Read the code")

    Conversation::Delivery.for(@conversation).step(key: "call_1", step: step, status: FirefightAi::AgentLoop::STEP_RUNNING)
  end
end
