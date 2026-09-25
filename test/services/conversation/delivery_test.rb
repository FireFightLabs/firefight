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
end
