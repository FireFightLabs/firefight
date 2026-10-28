require "application_system_test_case"

class SubscriptionConnectTest < ApplicationSystemTestCase
  Client = SubscriptionProxy::Client

  setup do
    @workspace = workspaces(:slack_workspace_one)
    sign_in(users(:alice), @workspace)
    subscription_proxy_up!
    Client.any_instance.stubs(:start_sign_in).returns(Client::SignIn.new(state: "xai-1", url: "https://accounts.x.ai/oauth2/device?user_code=SP7R-PYF3",
                                                                         user_code: "SP7R-PYF3", expires_at: 30.minutes.from_now))
    Client.any_instance.stubs(:models_for).returns([ proxy_model("grok-4.7", name: "Grok 4.7"), proxy_model("grok-4.7-build-fast", name: "Grok 4.7 Fast") ])
    Client.any_instance.stubs(:credential_models).returns(%w[grok-4.7 grok-4.7-build-fast])
    FirefightAi.stubs(:check_account)
  end

  test "a subscription is connected with the code its provider asks for, and its row says how much is left" do
    Client.any_instance.stubs(:sign_in_status).returns(:waiting)
    add_subscription_account!(@workspace, credential: "codex-ana.json",
                                          state: { "limit" => { "left_percent" => 38, "resets_at" => 2.hours.from_now.iso8601 } })
    visit settings_workspace_path

    click_button "Connect a subscription"
    find("[role=menuitem]", text: "SuperGrok").click

    within("[role=dialog]") do
      assert_text "SP7R-PYF3"
      assert_text "Waiting for you to finish signing in"
      page.save_screenshot(Rails.root.join("tmp/screenshots/subscription-device-code.png"))
    end

    Client.any_instance.stubs(:sign_in_status).returns(:done)
    started = SubscriptionSignIn.find_by!(workspace: @workspace, state: "xai-1")
    Client.any_instance.stubs(:credentials).returns([ proxy_credential(name: "xai-ana.json", provider: "xai", sign_in_id: started.id) ])
    Client.any_instance.stubs(:sign_in_result).returns(Client::SignInResult.new(credential: "xai-ana.json", workspace: @workspace.id, refused: nil))

    assert_text "SuperGrok subscription for ana@example.com connected.", wait: 10
    assert_no_selector "[role=dialog]"
    assert_text "38% of its limit left"
    page.scroll_to(find("[data-slot=card-title]", text: "AI accounts"), align: :top)
    page.save_screenshot(Rails.root.join("tmp/screenshots/subscription-connected.png"))
  end

  test "while the subscription service is down, Check again and Edit are disabled and say why" do
    add_subscription_account!(@workspace, credential: "codex-ana.json", state: { "limit" => { "left_percent" => 38 } })
    SubscriptionProxy::Check.failed!("down")
    visit settings_workspace_path

    check_again = find("button", text: "Check again")
    assert_predicate check_again, :disabled?
    check_again.find(:xpath, "..").hover
    assert_text SubscriptionProxy::UNAVAILABLE_FOR_CHANGES

    find("body").send_keys(:escape)
    within(find("tr", text: "ana@example.com")) { click_button "Actions" }
    assert_selector "[role=menuitem][data-disabled]", text: "Edit"
    page.save_screenshot(Rails.root.join("tmp/screenshots/subscription-blocked.png"))
  end

  test "a subscription is disconnected, not deleted, from its row menu through to the toast" do
    add_subscription_account!(@workspace, credential: "codex-ana.json", state: { "limit" => { "left_percent" => 38 } })
    Client.any_instance.expects(:delete).with("codex-ana.json")
    visit settings_workspace_path

    within(find("tr", text: "ana@example.com")) { click_button "Actions" }
    assert_no_selector "[role=menuitem]", text: "Delete"
    find("[role=menuitem]", text: "Disconnect").click

    within("[role=dialog]") do
      assert_text "Disconnect ChatGPT, ana@example.com?"
      page.save_screenshot(Rails.root.join("tmp/screenshots/subscription-disconnect.png"))
      click_button "Disconnect"
    end

    assert_text "ChatGPT subscription for ana@example.com was disconnected."
    page.save_screenshot(Rails.root.join("tmp/screenshots/subscription-disconnected.png"))
    assert_empty @workspace.workspace_ai_accounts.subscriptions
  end

  test "a browser sign-in asks for the address it lands on" do
    Client.any_instance.stubs(:start_sign_in).returns(Client::SignIn.new(state: "abc", url: "https://auth.openai.com/oauth/authorize?state=abc", user_code: nil, expires_at: nil))
    Client.any_instance.stubs(:sign_in_status).returns(:waiting)
    visit settings_workspace_path

    click_button "Connect a subscription"
    find("[role=menuitem]", text: "ChatGPT Plus or Pro").click

    within("[role=dialog]") do
      assert_text "http://localhost"
      assert_selector "a", text: "Sign in on auth.openai.com"
      page.save_screenshot(Rails.root.join("tmp/screenshots/subscription-paste.png"))
    end
  end

  test "a pasted address is handed back once, the checks never cut it short, and the connect says so" do
    Client.any_instance.stubs(:start_sign_in).returns(Client::SignIn.new(state: "abc", url: "https://auth.openai.com/oauth/authorize?state=abc", user_code: nil, expires_at: nil))
    Client.any_instance.stubs(:sign_in_status).returns(:waiting)
    Client.any_instance.expects(:finish_sign_in).once.with("codex", state: "abc", code: "the-code")
    Client.any_instance.stubs(:models_for).returns([ proxy_model("gpt-6.1-sol"), proxy_model("gpt-6-luna") ])
    Client.any_instance.stubs(:credential_models).returns(%w[gpt-6.1-sol gpt-6-luna])
    visit settings_workspace_path
    click_button "Connect a subscription"
    find("[role=menuitem]", text: "ChatGPT Plus or Pro").click

    within("[role=dialog]") do
      fill_in "Address your browser opened", with: "http://localhost:1455/auth/callback?code=the-code&state=abc"
      click_button "Connect"
      assert_text "Finishing the sign-in"
      assert_no_button "Connect"
    end

    Client.any_instance.stubs(:sign_in_status).returns(:done)
    started = SubscriptionSignIn.find_by!(workspace: @workspace, state: "abc")
    Client.any_instance.stubs(:credentials).returns([ proxy_credential(name: "codex-ana.json", sign_in_id: started.id) ])
    Client.any_instance.stubs(:sign_in_result).returns(Client::SignInResult.new(credential: "codex-ana.json", workspace: @workspace.id, refused: nil))

    assert_text "ChatGPT subscription for ana@example.com connected.", wait: 10
    assert_no_selector "[role=dialog]"
  end
end
