require "application_system_test_case"

class AgentChartCardTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    FeatureFlags.enable!(@workspace, FeatureFlags::AI_SRE)
    Entitlements.stubs(:allows?).returns(true)
    sign_in(users(:alice), @workspace)
  end

  test "metrics a tool returned are drawn as charts under its step, with a link to the live chart" do
    conversation = Conversation.start_personal!(workspace: @workspace, member: workspace_memberships(:alice_workspace_one))
    conversation.ask!("how is checkout doing")
    reply = conversation.chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    reply.ruby_llm_tool_calls.create!(tool_call_id: "call_1", name: "northflank_query_metrics", arguments: { "resource" => "checkout" })
    conversation.chat.add_message(role: :tool, content: "5xx responses of checkout", tool_call_id: "call_1")
    started = Time.utc(2026, 9, 25, 14, 0)
    points = ->(high) { (0..59).map { |minute| [ (started + minute.minutes).iso8601, minute > 40 ? high + (minute % 5) : minute % 3 ] } }
    Chat::Chart.record!(conversation.chat, "call_1", [
      { "title" => "5xx responses of checkout", "unit" => "count", "from" => started.iso8601, "to" => (started + 59.minutes).iso8601,
        "link" => "https://app.northflank.com/t/acme/project/shop/services/checkout",
        "series" => [ { "label" => "checkout-7f9c", "points" => points.call(30) }, { "label" => "checkout-2b1d", "points" => points.call(22) } ] },
      { "title" => "CPU of checkout", "unit" => "vCPU", "from" => started.iso8601, "to" => (started + 59.minutes).iso8601,
        "series" => [ { "label" => "checkout-7f9c", "points" => (0..59).map { |minute| [ (started + minute.minutes).iso8601, 0.2 + (minute > 40 ? 0.5 : 0) ] } } ] }
    ])
    conversation.note!("5xx responses on checkout jumped from about 1 to over 30 a minute at 14:41, on both containers.")
    conversation.reply_delivered!

    visit agent_chat_path(conversation)

    within("figure[aria-label='5xx responses of checkout']") do
      assert_selector "svg .recharts-line", count: 2
      assert_link "Open the live chart", href: "https://app.northflank.com/t/acme/project/shop/services/checkout"
    end
    assert_selector "figure[aria-label='CPU of checkout']"
    page.save_screenshot(Rails.root.join("tmp/screenshots/agent-chart-card.png"))
  end

  test "Northflank connects with a token and a project, as the provider's pack asks" do
    visit integrations_path(Integration::CONNECT_QUERY_PARAM => "northflank")

    assert_text "Connect Northflank"
    assert_field "API token", type: "password"
    assert_field "Project"
    page.save_screenshot(Rails.root.join("tmp/screenshots/northflank-connect.png"))
  end
end
