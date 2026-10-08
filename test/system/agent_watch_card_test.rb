require "application_system_test_case"

# Halon watching a release after its answer: the card says what it follows and for how long, each line it said later
# sits where it was said, and Stop asks first and confirms with a toast.
class AgentWatchCardTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    WorkspaceAdapter.stubs(:for).returns(stub_everything)
    sign_in(users(:alice), @workspace)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @alice)
    @conversation.ask!("I started the release. Tell me when run #46 finishes and when the web deploy starts and succeeds.")
    @conversation.chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT,
                                        content: "I am watching it. This usually takes about 18 minutes, I will watch for up to 40.")
    @conversation.reply_delivered!
    @watch = Chat::Watch.create!(chat: @conversation.chat, workspace: @workspace, asker: @alice, title: "release run #46 and the web deploy",
                                 expires_at: 40.minutes.from_now, usual_seconds: 18.minutes.to_i, limit_basis: Chat::Watch::BASIS_HISTORY)
    release = @watch.steps.create!(position: 0, label: "Release run #46", capability: Integrations::Capabilities::HISTORY, arguments: {})
    @watch.steps.create!(position: 1, label: "Web deploy", capability: Integrations::Capabilities::HISTORY, arguments: {}, report_start: true,
                         status: Chat::Watch::Step::STATUS_RUNNING, started_at: 2.minutes.ago)
    release.finished!(Chat::Watch::Step::STATUS_SUCCEEDED, at: 3.minutes.ago, started: 20.minutes.ago)
    travel_to(1.second.from_now) { @watch.updates.create!(kind: Chat::Watch::Update::KIND_MILESTONE, text: "Release run #46 succeeded after 17 minutes.") }
    travel_to(2.seconds.from_now) { @watch.updates.create!(kind: Chat::Watch::Update::KIND_MILESTONE, text: "Web deploy started.") }
  end

  test "the card shows the watch going with Stop, and Stop asks first then ends it with a toast" do
    visit agent_chat_path(@conversation)

    assert_text "Watching: release run #46 and the web deploy, up to 40 min"
    assert_text "It usually takes about 18 minutes."
    assert_text "Release run #46. Succeeded after 17 minutes."
    assert_text "Web deploy started."
    page.save_screenshot(Rails.root.join("tmp/screenshots/watch-card-active.png"))

    click_button "Stop"
    assert_text "Stop watching?"
    page.save_screenshot(Rails.root.join("tmp/screenshots/watch-card-confirm.png"))
    click_button "Stop watching"

    assert_text "Stopped watching release run #46 and the web deploy."
    assert_text "Stopped watching: release run #46 and the web deploy"
    assert_no_button "Stop"
    assert_text "Web deploy. Still running when the watch ended."
    page.save_screenshot(Rails.root.join("tmp/screenshots/watch-card-stopped.png"))
  end

  test "the header's search button is wider from small screens up and an icon on a phone" do
    search = "button[aria-label='Search the map, catalog and memory']"
    visit agent_chat_path(@conversation)
    assert_selector search, text: "Search"
    assert_operator find(search).native.size.width, :>=, 224
    page.save_screenshot(Rails.root.join("tmp/screenshots/header-search-desktop.png"))

    page.current_window.resize_to(390, 844)
    visit agent_chat_path(@conversation)
    assert_selector search
    assert_no_selector search, text: "Search"
    page.save_screenshot(Rails.root.join("tmp/screenshots/header-search-phone.png"))
  end
end
