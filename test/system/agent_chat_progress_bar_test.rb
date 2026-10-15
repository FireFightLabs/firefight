require "application_system_test_case"

# Seen live: the page's progress bar ran across the top whenever something in the chat changed, which read as the page
# reloading. Everything that stays on the chat shown shows no bar, however slow the server, and a visit that changes what
# is shown keeps it.
class AgentChatProgressBarTest < ApplicationSystemTestCase
  SLOW = 1.5

  # The test adapter only records broadcasts, and the live reload needs the browser to receive one.
  setup do
    @cable = ActionCable.server.config.cable
    ActionCable.server.config.cable = { "adapter" => "async" }
    ActionCable.server.restart
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    WorkspaceAdapter.stubs(:for).returns(stub_everything)
    sign_in(users(:alice), @workspace)
    ApplicationCable::Connection.any_instance.stubs(:signed_in_user).returns(users(:alice))
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @alice)
    @conversation.ask!("is the release out")
    @conversation.note!("Not yet.")
    @conversation.reply_delivered!
  end

  teardown do
    ActionCable.server.config.cable = @cable
    ActionCable.server.restart
  end

  test "Stop on an answer under way and pinning a chat in the list show no progress bar" do
    @conversation.ask!("and the worker?")
    @conversation.update!(answer_owed_since: 5.seconds.ago)
    visit agent_chat_path(@conversation)
    assert_selector "button[aria-label='Stop']"
    watch_page
    slow_server(SLOW)

    find("button[aria-label='Stop']").click
    assert_answered
    assert_toast Conversation::STOPPING

    find("button[aria-label='Actions for #{@conversation.reload.display_title}']", match: :first).click
    find("[role='menuitem']", text: "Pin").click
    assert_answered

    assert_stayed_in_place_for_each
    assert_no_progress_bar
  end

  test "a watch card's Stop and the live reload that moves the card show no progress bar" do
    watch = Chat::Watch.create!(chat: @conversation.chat, workspace: @workspace, asker: @alice, title: "Deploy finished",
                                expires_at: 40.minutes.from_now, usual_seconds: 18.minutes.to_i, limit_basis: Chat::Watch::BASIS_HISTORY)
    watch.steps.create!(position: 0, label: "Web deploy", capability: Integrations::Capabilities::HISTORY, arguments: {}, report_start: true,
                        status: Chat::Watch::Step::STATUS_RUNNING, started_at: 2.minutes.ago)
    visit agent_chat_path(@conversation)
    assert_text "Deploy finished"
    watch_page
    slow_server(SLOW)

    watch.update!(title: "Deploy and smoke test finished")
    page.document.synchronize(SLOW * 6) do
      Conversation::LiveDelivery.watch_moved(@conversation)
      raise Capybara::ElementNotFound, "the card did not move" unless page.has_text?("Deploy and smoke test finished", wait: SLOW + 1)
    end

    click_button "Stop"
    click_button "Stop watching"
    assert_toast 'Stopped watching "Deploy and smoke test finished".'
    assert_answered

    assert_no_progress_bar
  end

  test "opening another chat changes what is shown, so it keeps the progress bar" do
    other = Conversation.start_personal!(workspace: @workspace, member: @alice)
    other.ask!("what changed in checkout")
    other.note!("Nothing since Monday.")
    other.reply_delivered!
    visit agent_chat_path(@conversation)
    assert_text "Not yet."
    watch_page
    slow_server(SLOW)

    click_on "what changed in checkout", match: :first
    assert_text "Nothing since Monday."
    assert_answered

    assert page.evaluate_script("window.progressShown"), "opening a chat showed no progress bar"
  end

  private

  # Each change asked for only some props, so none visited the page whole.
  def assert_stayed_in_place_for_each
    assert page.evaluate_script("window.stillTheSamePage === true"), "the page was visited whole"
    page.evaluate_script("window.inertiaChanges").each { |change| assert change["only"], "#{change['url']} read the whole page back" }
  end
end
