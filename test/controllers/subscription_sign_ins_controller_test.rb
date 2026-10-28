require "test_helper"

class SubscriptionSignInsControllerTest < ActionDispatch::IntegrationTest
  Client = SubscriptionProxy::Client

  setup do
    @workspace = workspaces(:slack_workspace_one)
    sign_in(users(:alice), @workspace)
    subscription_proxy_up!
    Client.any_instance.stubs(:start_sign_in).returns(Client::SignIn.new(state: "xai-1", url: "https://accounts.x.ai/oauth2/device?user_code=SP7R", user_code: "SP7R", expires_at: 30.minutes.from_now))
  end

  def started = SubscriptionSignIn.find_by!(workspace: @workspace, state: "xai-1")

  test "starting a sign-in shows its code on the card, and nothing else happened yet to toast" do
    post subscription_sign_ins_path, params: { subscription: "supergrok" }, headers: { "Referer" => settings_workspace_path }

    assert_redirected_to settings_workspace_path
    assert_nil flash[:notice]
    get settings_workspace_path, headers: inertia_headers
    signed_in = inertia_props.fetch("aiSubscriptionSignIn")
    assert_equal [ "SuperGrok", "SP7R", "accounts.x.ai", true ], signed_in.values_at("name", "userCode", "host", "device")
  end

  test "a finished sign-in is connected and checked, and says so" do
    post subscription_sign_ins_path, params: { subscription: "supergrok" }
    Client.any_instance.stubs(:sign_in_status).returns(:done)
    Client.any_instance.stubs(:credentials).returns([ proxy_credential(name: "xai-ana.json", provider: "xai") ])
    Client.any_instance.stubs(:claim)
    Client.any_instance.stubs(:models_for).returns([ proxy_model("grok-4.7"), proxy_model("grok-4.7-build-fast") ])
    Client.any_instance.stubs(:credential_models).returns(%w[grok-4.7 grok-4.7-build-fast])
    FirefightAi.expects(:check_account).once

    post advance_subscription_sign_in_path(started)

    assert_equal "SuperGrok subscription for ana@example.com connected.", flash[:notice]
    assert @workspace.workspace_ai_accounts.subscriptions.exists?(proxy_credential: "xai-ana.json")
  end

  test "a sign-in still waiting answers quietly" do
    post subscription_sign_ins_path, params: { subscription: "supergrok" }
    Client.any_instance.stubs(:sign_in_status).returns(:waiting)

    post advance_subscription_sign_in_path(started)

    assert_nil flash[:notice]
    assert_nil flash[:alert]
  end

  test "a sign-in that will not finish says why" do
    post subscription_sign_ins_path, params: { subscription: "supergrok" }
    Client.any_instance.stubs(:sign_in_status).returns("Authentication failed")

    post advance_subscription_sign_in_path(started)

    assert_equal "The sign-in did not finish: Authentication failed. Start again.", flash[:alert]
  end

  test "cancelling ends the sign-in at the proxy" do
    post subscription_sign_ins_path, params: { subscription: "supergrok" }
    Client.any_instance.expects(:cancel_sign_in).with("xai-1")

    delete subscription_sign_in_path(started)

    assert_not SubscriptionSignIn.exists?(state: "xai-1")
  end

  test "a person cannot reach someone else's sign-in" do
    theirs = SubscriptionSignIn.create!(workspace: @workspace, started_by: workspace_memberships(:bob_workspace_one), subscription: "supergrok",
                                        proxy: "xai", state: "xai-2", url: "https://accounts.x.ai")

    post advance_subscription_sign_in_path(theirs)

    assert_response :not_found
  end
end
