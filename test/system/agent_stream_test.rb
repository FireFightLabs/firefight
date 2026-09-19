require "application_system_test_case"

class AgentStreamTest < ApplicationSystemTestCase
  # The test adapter only records broadcasts, and this test needs the browser to receive one.
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
    # The sign in helper stubs the controller, not the session the socket reads, so the socket is stubbed too.
    ApplicationCable::Connection.any_instance.stubs(:signed_in_user).returns(users(:alice))

    conversation = Conversation.start_personal!(workspace: workspace, member: member)
    conversation.ask!("Has checkout failed like this before?")

    visit agent_chat_path(conversation)
    assert_text "Has checkout failed"

    delivery = Conversation::LiveDelivery.new(conversation)
    open_stream(delivery)
    similar = Chat::Tools.step("search_similar", { "query" => "checkout failing" })
    delivery.step(key: "call_1", step: similar, status: :running)
    delivery.step(key: "call_1", step: similar, status: :done)
    delivery.step(key: "call_2", step: Chat::Tools.step("search_incidents", { "query" => "checkout" }), status: :running)
    delivery.chunk("Twice in the last quarter. ")
    delivery.chunk("INC-118 was the same connection pool exhaustion.")
    delivery.answered!("ignored")

    assert_text "Search similar"
    assert_text "INC-118 was the same connection pool exhaustion."
  end

  private

  # An accepted subscription can miss what is sent before its stream is live, so the turn is announced until the page shows it.
  def open_stream(delivery)
    50.times do
      delivery.thinking!
      return if page.has_text?("Working", wait: 0.2)
    end

    flunk "the page never opened its socket"
  end
end
