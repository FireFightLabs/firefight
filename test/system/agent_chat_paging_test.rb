require "application_system_test_case"

class AgentChatPagingTest < ApplicationSystemTestCase
  START = Time.utc(2026, 10, 1, 9, 0)
  THREAD = "section.agent-thread"
  SKELETON = "[role=status][aria-label='Loading the conversation']"
  # The skeleton may show for a moment only, so the page notes when it does.
  SKELETON_WATCH = <<~JS.freeze
    window.sawSkeleton = Boolean(document.querySelector(#{SKELETON.to_json}))
    new MutationObserver(() => {
      if (document.querySelector(#{SKELETON.to_json})) { window.sawSkeleton = true }
    }).observe(document.body, { childList: true, subtree: true })
  JS

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    sign_in(users(:alice), @workspace)
  end

  teardown do
    slow_network(latency: 0)
    page.driver.browser.execute_cdp("Page.removeScriptToEvaluateOnNewDocument", identifier: @watching) if @watching
  end

  test "a chat shows its composer at once and a skeleton where the conversation goes, then lands at its newest message" do
    chat = chat_with(turns: 60)
    watch_for_skeleton_from_the_start

    visit agent_chat_path(chat)

    assert_selector "#{THREAD} textarea"
    assert_selector THREAD, text: "Answer 59"
    assert page.evaluate_script("window.sawSkeleton"), "the skeleton showed while the conversation loaded"
    assert_no_selector SKELETON
    assert_no_selector "#{THREAD} p", exact_text: "Question 0"
    assert_in_view "Answer 59"
  end

  test "scrolling up loads the earlier messages a page at a time and keeps the place being read, until the first" do
    chat = chat_with(turns: 60)

    visit agent_chat_path(chat)
    assert_selector THREAD, text: "Answer 59"
    assert_no_text "Question 30"
    reading = "Answer 35"
    assert_text reading

    scroll_thread_to_top
    before = top_of(reading)
    assert_text "Question 30"
    assert_in_delta before, top_of(reading), 4, "the message being read stays where it was"

    scroll_thread_to_top
    assert_text "Question 0"
    assert_selector "#{THREAD} p", text: /\AQuestion \d+\z/, count: 60
    assert_no_text "Loading earlier messages"
  end

  test "opening a chat from the list shows the skeleton, then that chat, never the one open before" do
    first = chat_with(turns: 3, label: "First")
    second = chat_with(turns: 3, label: "Second")
    visit agent_chat_path(first)
    assert_text "First answer 2"
    page.execute_script(SKELETON_WATCH)
    slow_network

    within("aside.agent-chat-list") { click_link second.title }

    assert_text "Second answer 2", wait: 10
    assert page.evaluate_script("window.sawSkeleton"), "the skeleton showed while the conversation loaded"
    assert_no_text "First answer 2"
  end

  test "a hovered chat is read ahead, and opening it then shows it at once" do
    first = chat_with(turns: 3, label: "First")
    second = chat_with(turns: 3, label: "Second")
    visit agent_chat_path(first)
    assert_text "First answer 2"

    find("aside.agent-chat-list a", text: second.title).hover
    assert_read_ahead(second)
    slow_network(latency: 3_000)

    started = Time.current
    find("aside.agent-chat-list a", text: second.title).click
    assert_text "Second answer 2", wait: 2
    assert_operator Time.current - started, :<, 2, "the chat opened from what was read ahead, not over the slowed network"
  end

  test "asking after reading back keeps what was read and lands at the foot" do
    chat = chat_with(turns: 60)
    ConversationChannel.stubs(:broadcast_to)

    visit agent_chat_path(chat)
    assert_selector THREAD, text: "Answer 59"
    scroll_thread_to_top
    assert_text "Question 30"

    find("#{THREAD} textarea").set("And the worker?")
    find("#{THREAD} textarea").send_keys(:enter)
    assert_selector THREAD, text: "And the worker?"
    assert_text "Question 30"
    assert_in_view "And the worker?"
  end

  test "a change made from a card keeps what was read back, with no skeleton" do
    chat = chat_with(turns: 60)
    Chat::HandbookProposal.propose!(chat, title: "How web deploys", text: "Web deploys from main.", evidence: "The deploy log of web.")

    visit agent_chat_path(chat)
    assert_selector "section[aria-label='Handbook edit']"
    scroll_thread_to_top
    assert_text "Question 30"
    page.execute_script(SKELETON_WATCH)

    within("section[aria-label='Handbook edit']") { click_button "Dismiss" }

    assert_toast "The proposed"
    assert_text "Question 30"
    assert_not page.evaluate_script("window.sawSkeleton"), "the conversation on screen never went back to a skeleton"
  end

  private

  def chat_with(turns:, label: nil)
    conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
    conversation.ask!(said(label, "question", 0))
    chat = conversation.chat
    chat.messages.sole.update_columns(created_at: START)
    chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: said(label, "answer", 0)).update_columns(created_at: START + 1.second)
    (1...turns).each do |turn|
      chat.messages.create!(role: Chat::Message::ROLE_USER, content: said(label, "question", turn)).update_columns(created_at: START + turn.minutes)
      chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: said(label, "answer", turn)).update_columns(created_at: START + turn.minutes + 1.second)
    end
    conversation.reply_delivered!
    conversation.reload
  end

  def said(label, kind, turn) = [ label, label ? kind : kind.capitalize, turn ].compact.join(" ")

  # Every request from the browser waits this long for its answer.
  def slow_network(latency: 600)
    page.driver.browser.execute_cdp("Network.enable")
    page.driver.browser.execute_cdp("Network.emulateNetworkConditions", offline: false, latency: latency, downloadThroughput: -1, uploadThroughput: -1)
  end

  # From before the page's own scripts run, for a chat opened by its address.
  def watch_for_skeleton_from_the_start
    source = "document.addEventListener('DOMContentLoaded', () => { #{SKELETON_WATCH} })"
    @watching = page.driver.browser.execute_cdp("Page.addScriptToEvaluateOnNewDocument", source: source)["identifier"]
  end

  def scroll_thread_to_top
    page.execute_script("document.querySelector('#{THREAD} .overflow-y-auto').scrollTop = 0")
  end

  def top_of(text)
    page.evaluate_script(<<~JS)
      [...document.querySelectorAll("#{THREAD} p, #{THREAD} li")].find((element) => element.textContent.trim() === #{text.to_json}).getBoundingClientRect().top
    JS
  end

  def assert_in_view(text)
    assert_selector THREAD, text: text
    top = top_of(text)
    assert_operator top, :<, page.evaluate_script("window.innerHeight"), "#{text} is on screen"
    assert_operator top, :>, 0, "#{text} is on screen"
  end

  # Both halves of the chat, its composer's part and its conversation, have arrived.
  def assert_read_ahead(chat)
    script = "performance.getEntriesByType('resource').filter((entry) => entry.name.endsWith(#{agent_chat_path(chat).to_json})).length"
    deadline = Time.current + 5.seconds
    read = page.evaluate_script(script) until read.to_i >= 2 || Time.current > deadline
    assert_equal 2, read
  end
end
