require "application_system_test_case"

class AgentStreamTest < ApplicationSystemTestCase
  # The test adapter records broadcasts rather than delivering them, and this test is about the
  # browser receiving one, so the socket runs in this process instead.
  setup do
    @cable = ActionCable.server.config.cable
    ActionCable.server.config.cable = { "adapter" => "async" }
    ActionCable.server.restart
  end

  teardown do
    ActionCable.server.config.cable = @cable
    ActionCable.server.restart
  end

  test "the answer arrives as it is written" do
    workspace = workspaces(:slack_workspace_one)
    member = workspace_memberships(:alice_workspace_one)
    FeatureFlags.enable!(workspace, FeatureFlags::AI_SRE)
    Entitlements.stubs(:allows?).returns(true)
    sign_in(users(:alice), workspace)
    # The sign in helper stubs the controller rather than writing a session, which is what the
    # socket reads, so the socket is told who is watching the same way.
    ApplicationCable::Connection.any_instance.stubs(:signed_in_user).returns(users(:alice))

    conversation = Conversation.start_personal!(workspace: workspace, member: member)
    conversation.ask!("Has checkout failed like this before?")

    visit agent_chat_path(conversation)
    assert_text "Has checkout failed"

    delivery = Conversation::LiveDelivery.new(conversation)
    open_stream(delivery)
    delivery.step(key: "call_1", title: "Search similar", asked: [ [ "query", "checkout failing" ] ], status: :running)
    delivery.step(key: "call_1", title: "Search similar", asked: [ [ "query", "checkout failing" ] ], status: :done)
    delivery.step(key: "call_2", title: "Search incidents", asked: [ [ "query", "checkout" ] ], status: :running)
    delivery.chunk("Twice in the last quarter. ")
    delivery.chunk("INC-118 was the same connection pool exhaustion.")
    delivery.answered!("ignored")

    assert_text "Search similar"
    assert_text "INC-118 was the same connection pool exhaustion."
    take_screenshot
  end

  private

  # A subscription the server has accepted is not yet a stream it delivers on, and nothing sent in
  # between arrives. The turn is announced until the page shows it, which proves the stream is live.
  def open_stream(delivery)
    50.times do
      delivery.thinking!
      return if page.has_text?("Working", wait: 0.2)
    end

    flunk "the page never opened its socket"
  end
end
