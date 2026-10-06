require "application_system_test_case"

class AgentAttachmentsTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    FeatureFlags.enable!(@workspace, FeatureFlags::AI_SRE)
    Entitlements.stubs(:allows?).returns(true)
    sign_in(users(:alice), @workspace)
  end

  test "files are attached as chips, sent with the question, and shown on the message" do
    log = Rails.root.join("tmp/deploy-#{SecureRandom.hex(3)}.log")
    File.write(log, "10:02 deploy started\n10:03 payments worker crashed\n")
    visit agent_chats_path

    attach_file [ file_fixture("halon_graph.png").to_s, log.to_s ], make_visible: true

    within("[aria-label='Attached files']") do
      assert_text "halon_graph.png"
      assert_text File.basename(log)
      assert_selector "img"
    end
    assert_no_text "%"
    page.save_screenshot(Rails.root.join("tmp/screenshots/agent_attachments_chips.png").to_s)

    prompt.send_keys("What broke?", :enter)

    assert_selector "section.agent-thread-open"
    # The message shows at once with the browser's own copy of the image, so the test waits for the server's message,
    # which replaces it, before it reads what was saved or opens the image.
    assert_selector "button[aria-label='Open halon_graph.png'] img:not([src^='blob:'])"
    assert_link File.basename(log)
    message = @workspace.conversations.sole.chat.messages.find_by!(role: Chat::Message::ROLE_USER)
    assert_equal [ "halon_graph.png", File.basename(log) ], message.attached_files.map(&:filename)
    page.save_screenshot(Rails.root.join("tmp/screenshots/agent_attachments_sent.png").to_s)

    find("button[aria-label='Open halon_graph.png']").click
    within("[role='dialog']") do
      assert_selector "img[alt='halon_graph.png']"
      assert_link "Open the original"
    end
    page.save_screenshot(Rails.root.join("tmp/screenshots/agent_attachments_full_size.png").to_s)
  ensure
    FileUtils.rm_f(log)
  end

  # An image opened the moment it was sent once closed by itself when the server's message replaced the one
  # shown on sending.
  test "an image opened before the server answers stays open when the server's message takes its place" do
    ConversationReplyJob.stubs(:perform_later).with { sleep 1.5 }
    visit agent_chats_path

    attach_file file_fixture("halon_graph.png").to_s, make_visible: true
    prompt.send_keys("What broke?")
    assert_selector "button[aria-label='Send']:not([disabled])"
    prompt.send_keys(:enter)

    find("button[aria-label='Open halon_graph.png'] img[src^='blob:']").click
    within("[role='dialog']") { assert_selector "img[alt='halon_graph.png'][src^='blob:']" }

    assert_selector "button[aria-label='Open halon_graph.png'] img:not([src^='blob:'])"
    within("[role='dialog']") { assert_selector "img[alt='halon_graph.png']:not([src^='blob:'])" }
  end

  test "a file Halon does not read says what is accepted and holds the message until it is removed" do
    zip = Rails.root.join("tmp/dump-#{SecureRandom.hex(3)}.zip")
    File.binwrite(zip, "PK\u0003\u0004#{"\u0000" * 20}")
    visit agent_chats_path

    prompt.send_keys("Look at this")
    attach_file zip.to_s, make_visible: true

    assert_text "#{File.basename(zip)} is not a file Halon reads. #{Chat::Attachment::ACCEPTED}"
    assert_selector "button[aria-label='Send'][disabled]"
    page.save_screenshot(Rails.root.join("tmp/screenshots/agent_attachments_refused.png").to_s)

    find("button[aria-label='Remove #{File.basename(zip)}']").click

    assert_no_text "is not a file Halon reads"
    assert_selector "button[aria-label='Send']:not([disabled])"
  ensure
    FileUtils.rm_f(zip)
  end

  test "the + menu attaches files, and the page says before sending when the model cannot read images" do
    conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
    conversation.ask!("hello")
    conversation.chat.update!(model: "gpt-3.5-turbo")
    conversation.reply_delivered!
    visit agent_chat_path(conversation)

    find("button[aria-label='Add attachments and sources']").click
    assert_text "Attach files"

    attach_file file_fixture("halon_graph.png").to_s, make_visible: true

    assert_text Chat::Attachment::IMAGES_UNREAD
    page.save_screenshot(Rails.root.join("tmp/screenshots/agent_attachments_no_vision.png").to_s)
  end

  test "a pasted screenshot is attached" do
    visit agent_chats_path
    png = Base64.strict_encode64(file_fixture("halon_graph.png").binread)

    page.execute_script(<<~JS, png)
      const bytes = Uint8Array.from(atob(arguments[0]), (character) => character.charCodeAt(0))
      const data = new DataTransfer()
      data.items.add(new File([bytes], "pasted.png", { type: "image/png" }))
      const input = document.querySelector("textarea[aria-label='Prompt']")
      input.dispatchEvent(new ClipboardEvent("paste", { clipboardData: data, bubbles: true, cancelable: true }))
    JS

    within("[aria-label='Attached files']") { assert_text "pasted.png" }
  end

  private

  def prompt = find("textarea[aria-label='Prompt']")
end
