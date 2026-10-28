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

  test "a finished sign-in nobody claimed is removed once nothing can claim it, and a claimed one never is" do
    add_subscription_account!(@workspace, credential: "codex-ana.json")
    credentials = [ proxy_credential(name: "codex-ana.json", created_at: 2.hours.ago),
                    proxy_credential(name: "codex-stray.json", created_at: 2.hours.ago),
                    proxy_credential(name: "codex-new.json", created_at: 1.minute.ago) ]
    Client.any_instance.expects(:delete).with("codex-stray.json").once

    SubscriptionProxy::Accounts.sweep_unclaimed!(credentials)
  end
end
