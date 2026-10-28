require "test_helper"

class SubscriptionProxy::HealthCheckTest < ActiveSupport::TestCase
  ISOLATED = { "routing" => { "force-model-prefix" => true, "session-affinity" => true, "strategy" => "round-robin" } }.freeze

  setup { configure_subscription_proxy! }

  test "a proxy that answers with workspaces kept apart passes, and is usable" do
    stub_proxy(proxy_response(200, { status: "ok" }, "X-Cpa-Version" => "v8.0.28"), proxy_response(200, ISOLATED))

    SubscriptionProxy::HealthCheck.run

    check = SubscriptionProxy::Check.current
    assert_nil check.failing_since
    assert_equal "v8.0.28", check.version
    assert_predicate SubscriptionProxy, :usable?
  end

  test "a proxy that would let one workspace reach another's subscription fails, and is used by nobody" do
    loose = { "routing" => { "force-model-prefix" => false, "session-affinity" => true } }
    stub_proxy(proxy_response(200, { status: "ok" }), proxy_response(200, loose))

    SubscriptionProxy::HealthCheck.run

    assert_match "force-model-prefix", SubscriptionProxy::Check.current.last_error
    refute_predicate SubscriptionProxy, :usable?
  end

  test "a proxy that does not answer fails, keeping the time it first failed, and passing again clears it" do
    Net::HTTP.stubs(:start).raises(Errno::ECONNREFUSED)
    SubscriptionProxy::HealthCheck.run
    first = SubscriptionProxy::Check.current.failing_since

    travel 5.minutes do
      SubscriptionProxy::HealthCheck.run
      assert_equal first, SubscriptionProxy::Check.current.reload.failing_since
      assert_match "could not reach", SubscriptionProxy::Check.current.last_error
    end

    Net::HTTP.unstub(:start)
    stub_proxy(proxy_response(200, { status: "ok" }), proxy_response(200, ISOLATED))
    SubscriptionProxy::HealthCheck.run
    assert_predicate SubscriptionProxy, :usable?
  end

  test "an install without the proxy checks nothing" do
    SubscriptionProxy.unstub(:settings)
    SubscriptionProxy::Client.any_instance.expects(:transport).never

    SubscriptionProxy::HealthCheck.run

    assert_nil SubscriptionProxy::Check.current
    refute_predicate SubscriptionProxy, :usable?
  end
end
