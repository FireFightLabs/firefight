require "test_helper"

class SignInRateLimitsTest < ActionDispatch::IntegrationTest
  setup do
    FeatureFlags.enable_globally!(FeatureFlags::SELF_SERVE_SIGNUP)
    @store = Rack::Attack.cache.store
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
  end

  teardown do
    Rack::Attack.cache.store = @store
  end

  test "one address asks for at most five links a minute" do
    5.times { |index| post email_sign_in_path, params: { email: "ip-#{index}@example.com" } }
    assert_response :redirect

    post email_sign_in_path, params: { email: "ip-6@example.com" }

    assert_response :too_many_requests
    assert_equal "email sign-in link by ip", request.env["rack.attack.matched"]
  end

  test "one inbox gets at most five links an hour, from any address and in any case" do
    5.times do |index|
      post email_sign_in_path, params: { email: "Target@Example.com" }, env: { "REMOTE_ADDR" => "10.0.0.#{index + 1}" }
    end
    assert_response :redirect

    post email_sign_in_path, params: { email: "target@example.com" }.to_json,
      headers: { "CONTENT_TYPE" => "application/json" }, env: { "REMOTE_ADDR" => "10.0.0.99" }

    assert_response :too_many_requests
    assert_equal "email sign-in link by email", request.env["rack.attack.matched"]
    assert_match "an hour", response.body
  end

  test "one address confirms at most twenty links a minute" do
    20.times { post consume_email_sign_in_path, params: { token: "guess" } }
    assert_response :redirect

    post consume_email_sign_in_path, params: { token: "guess" }

    assert_response :too_many_requests
  end
end
