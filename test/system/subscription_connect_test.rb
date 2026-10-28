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
    Client.any_instance.stubs(:claim)
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
    Client.any_instance.stubs(:credentials).returns([ proxy_credential(name: "xai-ana.json", provider: "xai") ])

    assert_text "SuperGrok subscription for ana@example.com connected.", wait: 10
    assert_no_selector "[role=dialog]"
    assert_text "38% of its limit left"
    page.scroll_to(find("[data-slot=card-title]", text: "AI accounts"), align: :top)
    page.save_screenshot(Rails.root.join("tmp/screenshots/subscription-connected.png"))
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
end
