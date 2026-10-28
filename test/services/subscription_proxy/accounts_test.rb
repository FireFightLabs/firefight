require "test_helper"

class SubscriptionProxy::AccountsTest < ActiveSupport::TestCase
  Client = SubscriptionProxy::Client

  setup do
    @workspace = workspaces(:slack_workspace_one)
    subscription_proxy_up!
    Client.any_instance.stubs(:models_for).returns([ proxy_model("gpt-6.1-sol"), proxy_model("gpt-6-luna") ])
    Client.any_instance.stubs(:credential_models).returns(%w[gpt-6.1-sol gpt-6-luna])
  end

  def codex_limit(used:, resets_in:, observed: Time.current)
    { quota: { "x-codex-primary-used-percent" => used.to_s, "x-codex-primary-reset-after-seconds" => resets_in.to_i.to_s }, quota_observed_at: observed }
  end

  test "a ChatGPT sign-in says how much of its limit is left and when it resets, and a broken one needs signing in again" do
    left = add_subscription_account!(@workspace, credential: "codex-ana.json")
    broken = add_subscription_account!(@workspace, credential: "codex-ben.json", email: "ben@example.com")
    Client.any_instance.stubs(:prioritize)
    credentials = [ proxy_credential(name: "codex-ana.json", **codex_limit(used: 62, resets_in: 2.hours)),
                    proxy_credential(name: "codex-ben.json", status: "error") ]

    SubscriptionProxy::Accounts.new(@workspace).sync!(credentials)

    limit = left.reload.proxy_limit
    assert_equal 38, limit["left_percent"]
    assert_in_delta 2.hours.from_now, Time.zone.parse(limit["resets_at"]), 5
    assert_equal :signed_out, broken.reload.state
  end

  test "a plan that declares no limit signals says nothing of how much is left, whatever the proxy kept" do
    account = add_subscription_account!(@workspace, subscription: "supergrok", credential: "xai-ana.json")
    Client.any_instance.stubs(:prioritize)

    SubscriptionProxy::Accounts.new(@workspace).sync!([ proxy_credential(name: "xai-ana.json", provider: "xai", **codex_limit(used: 62, resets_in: 2.hours)) ])

    assert_nil account.reload.proxy_limit["left_percent"]
    assert_equal false, account.proxy_limit["reported"]
  end

  test "a sign-in at its limit says until when" do
    account = add_subscription_account!(@workspace, credential: "codex-ana.json")
    Client.any_instance.stubs(:prioritize)
    back_at = 3.hours.from_now

    SubscriptionProxy::Accounts.new(@workspace).sync!([ proxy_credential(name: "codex-ana.json", status: "error", unavailable: true, next_retry_after: back_at) ])

    assert_equal :limit_reached, account.reload.state
    assert_in_delta back_at, Time.zone.parse(account.proxy_limit["reached_until"]), 1
  end

  test "new conversations go first to the sign-in with room whose limit resets soonest, and one at its limit goes last" do
    later = add_subscription_account!(@workspace, credential: "codex-later.json", email: "later@example.com")
    sooner = add_subscription_account!(@workspace, credential: "codex-sooner.json", email: "sooner@example.com")
    spent = add_subscription_account!(@workspace, credential: "codex-spent.json", email: "spent@example.com")
    credentials = [
      proxy_credential(name: "codex-later.json", **codex_limit(used: 10, resets_in: 5.hours)),
      proxy_credential(name: "codex-sooner.json", **codex_limit(used: 80, resets_in: 1.hour)),
      proxy_credential(name: "codex-spent.json", status: "error", unavailable: true, next_retry_after: 30.minutes.from_now)
    ]
    given = {}
    Client.any_instance.stubs(:prioritize).with { |name, priority| given[name] = priority }

    SubscriptionProxy::Accounts.new(@workspace).sync!(credentials)

    assert_equal [ sooner, later, spent ].map(&:proxy_credential), given.sort_by { |_name, priority| -priority }.map(&:first)
  end

  test "an unchanged order is not sent again" do
    add_subscription_account!(@workspace, credential: "codex-ana.json", state: { "priority" => 1 })
    Client.any_instance.expects(:prioritize).never

    SubscriptionProxy::Accounts.new(@workspace).sync!([ proxy_credential(name: "codex-ana.json") ])
  end

  test "a credential the proxy no longer holds needs signing in again, and the workspace's other accounts are still brought up to date" do
    gone = add_subscription_account!(@workspace, credential: "codex-gone.json")
    held = add_subscription_account!(@workspace, credential: "codex-held.json", email: "ben@example.com")
    Client.any_instance.stubs(:credential_models).with("codex-gone.json", anything).raises(SubscriptionProxy::NotFound.new("gone", status: 404))
    Client.any_instance.stubs(:prioritize)

    SubscriptionProxy::Accounts.new(@workspace).sync!([ proxy_credential(name: "codex-held.json", **codex_limit(used: 50, resets_in: 1.hour)) ])

    assert_equal :signed_out, gone.reload.state
    assert_equal 50, held.reload.proxy_limit["left_percent"]
  end

  test "a subscription turns off as it is, even when the model it was saved with is gone, and one the proxy lost still turns off" do
    account = add_subscription_account!(@workspace, credential: "codex-gone.json")
    account.update_columns(models: { "main" => "gpt-retired", "fast" => "gpt-6-luna" })
    Client.any_instance.stubs(:switch).raises(SubscriptionProxy::NotFound.new("auth file not found", status: 404))

    SubscriptionProxy::Accounts.new(@workspace).switch!(account, on: false)

    assert_not account.reload.enabled
  end

  test "without the proxy set up a subscription can still be disconnected" do
    account = add_subscription_account!(@workspace, credential: "codex-ana.json")
    SubscriptionProxy.unstub(:settings)
    Client.any_instance.expects(:delete).never

    SubscriptionProxy::Accounts.new(@workspace).disconnect!(account)

    assert_not WorkspaceAiAccount.exists?(account.id)
  end

  test "a credential nobody claimed goes once nothing can claim it, and a claimed one never does" do
    add_subscription_account!(@workspace, credential: "codex-ana.json")
    credentials = [ proxy_credential(name: "codex-ana.json", created_at: 2.hours.ago),
                    proxy_credential(name: "codex-stray.json", created_at: 2.hours.ago),
                    proxy_credential(name: "codex-untimed.json", created_at: nil),
                    proxy_credential(name: "codex-new.json", created_at: 1.minute.ago) ]
    Client.any_instance.expects(:delete).with("codex-stray.json").once
    Client.any_instance.expects(:delete).with("codex-untimed.json").once

    SubscriptionProxy::Accounts.sweep_unclaimed!(credentials)
  end

  test "a credential a sign-in made stays while that sign-in waits, and goes once it ended without an account" do
    waiting = SubscriptionSignIn.create!(workspace: @workspace, subscription: "chatgpt", proxy: "codex", state: "w", url: "https://auth.openai.com")
    cancelled = SubscriptionSignIn.create!(workspace: @workspace, subscription: "chatgpt", proxy: "codex", state: "c", url: "https://auth.openai.com",
                                           status: SubscriptionSignIn::STATUS_CANCELLED)
    credentials = [ proxy_credential(name: "codex-waiting.json", sign_in_id: waiting.id),
                    proxy_credential(name: "codex-late.json", sign_in_id: cancelled.id),
                    proxy_credential(name: "codex-forgotten.json", sign_in_id: SecureRandom.uuid) ]
    Client.any_instance.expects(:delete).with("codex-late.json").once
    Client.any_instance.expects(:delete).with("codex-forgotten.json").once

    SubscriptionProxy::Accounts.sweep_unclaimed!(credentials)
  end
end
