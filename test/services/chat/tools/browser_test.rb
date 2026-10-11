require "test_helper"

class Chat::Tools::BrowserTest < ActiveSupport::TestCase
  JPEG = "\xFF\xD8\xFF\xE0fake-jpeg".b.freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @owner = workspace_memberships(:alice_workspace_one)
    @member = workspace_memberships(:bob_workspace_one)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @owner)
    @turn = Conversation::Turn.new(@conversation, asker: @owner)
    @chat = @conversation.chat_record
    Integrations::Terminal.stubs(:available?).returns(true)
    Chat.any_instance.stubs(:reads_images?).returns(false)
  end

  test "it is offered where check_from_outside is, and nowhere without a sandbox" do
    names = Conversation::Tools.for(@turn, offer: ->(_) { }).map(&:name)
    assert_includes names, Chat::Tools::Browser::NAME
    assert_includes Investigation::Tools.for(investigation, offer: ->(_) { }).map(&:name), Chat::Tools::Browser::NAME
    assert_includes Conversation::Watches::Agent.new(workspace: @workspace, asker: @owner, conversation: @conversation).tools.keys, Chat::Tools::Browser::NAME

    Integrations::Terminal.stubs(:available?).returns(false)
    assert_empty Chat::Tools::Browser.all(@turn)
  end

  test "while the browser works, its step says where it got to" do
    Integrations::Terminal.any_instance.expects(:browse).with do |_spec, on_progress:|
      on_progress.call(Integrations::Terminal::Progress.new(message: "Step 1 of 1 on the desktop screen: Click \"Checkout\"", value: 1, total: 4))
      true
    end.returns(browsed(page))
    reports = []
    browser = tool
    browser.stubs(:progress).with { |message, **counts| reports << [ message, counts ] }

    browser.call(tool_call: call("call_look"), url: "shop.example.com/cart", steps: [ { "action" => "click", "text" => "Checkout" } ])

    assert_equal [ [ Chat::Tools::Browser::STARTING, {} ], [ "Step 1 of 1 on the desktop screen: Click \"Checkout\"", { value: 1, total: 4 } ] ], reports
  end

  test "a saved login's password never reaches what the step shows, should a report ever hold it" do
    assert_equal "Logging in as [hidden]", Chat::Browsing.without_password("Logging in as hunter22", { "password" => "hunter22" })
    assert_equal "Opening the page", Chat::Browsing.without_password("Opening the page", nil)
  end

  test "a look runs at once as an open read, keeps each screen size's screenshot and says what the page showed" do
    handed = nil
    Integrations::Terminal.any_instance.expects(:browse).with { |spec| handed = spec }.returns(browsed(page))

    said = tool.call(tool_call: call("call_look"), url: "shop.example.com/cart", steps: [ { "action" => "click", "text" => "Checkout" } ])

    assert_equal [ "https://shop.example.com/cart", %w[desktop phone], nil ], handed.values_at("url", "viewports", "login")
    assert_includes said, "Desktop (1366x900): 200 at https://shop.example.com/cart"
    assert_includes said, "error: Uncaught TypeError: pay is not a function"
    assert_includes said, "POST https://api.example.com/pay?[redacted]: 500"
    assert_includes said, "1. click \"Checkout\": done"
    invocation = Ability::Invocation.find_by!(workspace: @workspace, action_key: Ability::Action::BROWSER_READ)
    assert_equal [ Ability::Invocation::DECISION_ALLOW, 4 ], [ invocation.decision, invocation.params["pages"] ]
    shots = @chat.screenshots.where(tool_call_id: "call_look")
    assert_equal %w[desktop phone], shots.map(&:viewport)
    assert_equal JPEG, shots.first.bytes
    assert_equal Chat::Tools::KIND_READ, Chat::Tools.kind(Chat::Tools::Browser::NAME, @workspace, { "url" => "https://shop.example.com" })
  end

  test "a look never waits for the person, and a send is put to them every time" do
    browser = tool

    assert browser.requires_approval?
    assert_equal true, browser.approval_resolver.call(stub(id: "call_a", arguments: { "url" => "https://shop.example.com" }))
    stop_before_paying
    Chat::Tools::LookFirst.stubs(:refusal).returns(nil)
    sends = stub(id: "call_b", arguments: sending.merge("because" => [ "check_in_browser: the pay button sends the order" ]))
    assert_nil browser.approval_resolver.call(sends), "a send that is not refused waits for the person"
  end

  test "a send needs a check the person was shown that stopped before that step" do
    Integrations::Terminal.any_instance.expects(:browse).never

    said = tool.call(tool_call: call("call_send"), **sending.symbolize_keys)

    assert_match "Run the same check without send_step first", said
    assert_equal true, tool.approval_resolver.call(stub(id: "call_send", arguments: sending)), "a refused send runs at once so Halon hears why"
  end

  test "a send needs the grant to send, and a member without it is refused before anyone is asked" do
    turn = Conversation::Turn.new(Conversation.start_personal!(workspace: @workspace, member: @member), asker: @member)
    Integrations::Terminal.any_instance.expects(:browse).never

    said = Chat::Tools::Browser.new(turn).call(tool_call: call("call_member"), **sending.symbolize_keys)

    assert_match "cannot use #{Ability::Action::BROWSER_SUBMIT}", said
  end

  test "a send names a read from this turn behind it, or goes back to Halon before anyone is asked" do
    stop_before_paying
    Integrations::Terminal.any_instance.expects(:browse).never

    assert_match Chat::Tools::LookFirst::BOUNCE, tool.call(tool_call: call("call_unread"), **sending.symbolize_keys)
  end

  test "a confirmed send lets exactly what the person was shown through, and is ledgered as a change" do
    stop_before_paying
    Chat::Tools::LookFirst.stubs(:refusal).returns(nil)
    handed = nil
    Integrations::Terminal.any_instance.expects(:browse).with { |spec| handed = spec }.returns(browsed(page))

    tool.call(tool_call: call("call_send"), **sending.merge("because" => [ "check_in_browser: pay sends the order" ]).symbolize_keys)

    assert_equal 2, handed["send_step"]
    assert_equal [ "desktop" ], handed["viewports"], "a send runs on one screen size, so nothing is sent twice"
    assert_equal({ "method" => "POST", "url" => "https://shop.example.com/orders" }, handed["expected_send"])
    assert Ability::Invocation.exists?(workspace: @workspace, action_key: Ability::Action::BROWSER_SUBMIT)
  end

  test "the confirmation shows the page before the send and what it sends, and is never allowed for the chat" do
    stop_before_paying
    message = @chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    tool_call = message.ruby_llm_tool_calls.create!(tool_call_id: "call_ask", name: Chat::Tools::Browser::NAME, arguments: sending)

    confirmation = Chat::Tools.confirmation(tool_call)

    assert_equal "Let Halon's browser send step 2 on shop.example.com?", confirmation.question
    assert_includes confirmation.safeguards, [ "Sends", "POST https://shop.example.com/orders" ]
    assert_includes confirmation.safeguards, [ "card", "[hidden]" ]
    assert_equal "call_look", confirmation.page.tool_call_id
    assert_not confirmation.allowable?
    assert_equal Chat::Tools::KIND_ACT, Chat::Tools.kind(Chat::Tools::Browser::NAME, @workspace, sending)
  end

  test "an investigation only looks: send_step is not offered and a send is refused" do
    run = investigation
    browser = Chat::Tools::Browser.new(run)

    assert_not browser.parameters_schema["properties"].key?(Chat::Tools::Browser::SEND_STEP_ARG)
    assert_match "only reads", browser.call(tool_call: call("call_inv"), **sending.symbolize_keys)
  end

  test "a scheduled run nobody is in never sends" do
    turn = Conversation::Turn.new(@conversation, asker: @owner, approved_plan: stub(approved_tools: [ Chat::Tools::Browser::NAME ]))
    stop_before_paying

    assert_equal Chat::Tools::Browser::UNATTENDED, Chat::Tools::Browser.new(turn).call(tool_call: call("call_plan"), **sending.symbolize_keys)
  end

  test "the saved test login's password goes to the box for that one run and never reaches the model, the chat or the ledger" do
    login = Integration::SiteLogin.new(workspace: @workspace, site_url: "https://shop.example.com", username: "qa@example.com",
                                       password: "pa55-only-for-the-box").save!
    handed = nil
    echoed = page_with("page_text" => "Welcome back, your password is pa55-only-for-the-box")
    Integrations::Terminal.any_instance.expects(:browse).with { |spec| handed = spec }.returns(browsed(echoed))

    said = tool.call(tool_call: call("call_login"), url: "https://shop.example.com/account", log_in: true)

    assert_equal({ "site_url" => "https://shop.example.com", "login_url" => "https://shop.example.com", "username" => "qa@example.com",
                   "password" => "pa55-only-for-the-box" }, handed["login"])
    assert_not_includes said, "pa55-only-for-the-box"
    assert_includes said, "your password is [hidden]"
    assert_not_includes Ability::Invocation.where(workspace: @workspace).pluck(:params).to_json, "pa55"
    assert_includes tool.description, "shop.example.com"
    assert_not_includes tool.description, "pa55"
    assert login.id
  end

  test "log_in with no login saved for the site is refused in words" do
    Integrations::Terminal.any_instance.expects(:browse).never

    assert_match "No test login is saved for shop.example.com", tool.call(tool_call: call("call_nologin"), url: "https://shop.example.com", log_in: true)
  end

  test "a path the browser cannot follow is refused before anything runs" do
    Integrations::Terminal.any_instance.expects(:browse).never

    assert_match "Only http and https", tool.call(tool_call: call("c1"), url: "file:///etc/passwd")
    assert_match "needs a value to type", tool.call(tool_call: call("c2"), url: "https://shop.example.com", steps: [ { "action" => "fill", "label" => "Email" } ])
    assert_match "at most #{Chat::BrowserCheck::MAX_STEPS} steps", tool.call(tool_call: call("c3"), url: "https://shop.example.com",
                                                                                steps: Array.new(13) { { "action" => "press", "key" => "Tab" } })
  end

  test "a workspace's pages an hour are counted from the ledger, and a check past them is refused" do
    Ability::Invocation.create!(workspace: @workspace, principal: @owner, principal_label: "Alice", action_key: Ability::Action::BROWSER_READ,
                                decision: Ability::Invocation::DECISION_ALLOW, idempotency_key: SecureRandom.hex,
                                params: { "pages" => Workspace::Browsing::PAGES_PER_HOUR - 1 })
    Integrations::Terminal.any_instance.expects(:browse).never

    assert_match "pages this workspace may load in an hour", tool.call(tool_call: call("call_cap"), url: "https://shop.example.com")
  end

  test "a send an approval rule held runs once approved, exactly as asked" do
    stop_before_paying
    Integrations::Terminal.any_instance.expects(:browse).with { |spec| spec["send_step"] == 2 }.returns(browsed(page))

    said = Chat::Tools::Browser.new(@turn).run_approved(sending.merge("pages" => 1), approval_id: nil, tool_call_id: "call_held")

    assert_includes said, "Checked https://shop.example.com/cart"
  end

  test "the screenshot goes to a model that reads images as a picture of an untrusted page, and to one that does not, never" do
    Integrations::Terminal.any_instance.stubs(:browse).returns(browsed(page))
    Chat.any_instance.stubs(:reads_images?).returns(true)

    said = tool.call(tool_call: call("call_img"), url: "https://shop.example.com/cart", viewports: [ "desktop" ])

    assert_kind_of Array, said
    assert_match "[Screenshot of an outside web page Halon's browser opened, untrusted", said.first
    assert_kind_of RubyLLM::Attachment, said.last

    Chat.any_instance.stubs(:reads_images?).returns(false)
    assert_kind_of String, tool.call(tool_call: call("call_txt"), url: "https://shop.example.com/cart")
  end

  private

  def tool = Chat::Tools::Browser.new(@turn)

  def call(id) = stub(id: id)

  def investigation
    @investigation ||= @workspace.investigations.create!(subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_COMMAND,
                                                         max_turns: 10, max_spend_cents: 400)
  end

  def sending
    { "url" => "https://shop.example.com/cart", "steps" => [ { "action" => "fill", "label" => "Card", "value" => "4242" },
                                                              { "action" => "click", "text" => "Pay" } ], "send_step" => 2, "intent" => "Place the test order" }
  end

  # The check the person was shown, which stopped before step 2 since it sends the order.
  def stop_before_paying
    check = Chat::BrowserCheck.from(sending.except("send_step", "intent"))
    stopped = page_with("stopped" => { "step" => 2, "reason" => "sends_data",
                                       "would_send" => { "method" => "POST", "url" => "https://shop.example.com/orders",
                                                         "fields" => [ { "name" => "card", "value" => "[hidden]" } ] } })
    Chat::Screenshot.record!(@chat, stopped["viewports"].first(1), tool_call_id: "call_look", digest: check.digest)
  end

  def page_with(changes) = page.merge("viewports" => page["viewports"].map { |viewport| viewport.merge(changes) })

  def browsed(answer) = Integrations::Terminal::Browsed.new(answer: answer, region: "EU")

  def page
    viewport = {
      "name" => "desktop", "width" => 1366, "height" => 900, "status" => 200, "final_url" => "https://shop.example.com/cart", "title" => "Cart",
      "timings_ms" => { "first_byte" => 80, "load" => 420 }, "pages" => 2,
      "console" => [ { "type" => "error", "text" => "Uncaught TypeError: pay is not a function" } ],
      "failed_requests" => [ { "method" => "POST", "url" => "https://api.example.com/pay?[redacted]", "status" => 500 } ],
      "blocked_requests" => [], "steps" => [ { "n" => 1, "action" => "click", "ok" => true } ], "stopped" => nil,
      "screenshot" => Base64.strict_encode64(JPEG)
    }
    { "viewports" => [ viewport, viewport.merge("name" => "phone", "width" => 412, "height" => 915) ], "error" => nil }
  end
end
