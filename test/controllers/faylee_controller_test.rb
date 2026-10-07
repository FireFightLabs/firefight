require "test_helper"

class FayleeControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
  end

  test "verification returns the configured token without signing in" do
    Rails.configuration.x.stubs(:faylee_verification_token).returns("test-verification-token")

    get "/.well-known/faylee-verification.txt"

    assert_response :success
    assert_equal "test-verification-token", response.body
    assert_equal "text/plain", response.media_type
  end

  test "verification is not found when no token is configured" do
    Rails.configuration.x.stubs(:faylee_verification_token).returns(nil)

    get "/.well-known/faylee-verification.txt"

    assert_response :not_found
    assert_nil response.headers["Location"]
  end

  test "the widget and its policy load inside a workspace" do
    Rails.configuration.x.stubs(:faylee_site_id).returns("test-site-id")
    sign_in(users(:alice), @workspace)

    get dashboard_path

    assert_response :success
    nonce = response.body[%r{<script[^>]+src="https://app\.faylee\.app/widget\.js"[^>]+data-site="test-site-id"[^>]+nonce="([^"]+)"}, 1]
    assert_not_nil nonce
    assert_equal response.body[/<meta name="csp-nonce" content="([^"]+)"/, 1], nonce
    assert_match(%r{script-src[^;]*https://app\.faylee\.app}, policy_header)
    assert_match(%r{connect-src[^;]*https://app\.faylee\.app}, policy_header)
    assert_match(%r{frame-src[^;]*https://app\.faylee\.app}, policy_header)
  end

  test "sign-in pages never load the widget or open the policy to it" do
    Rails.configuration.x.stubs(:faylee_site_id).returns("test-site-id")

    get login_path

    assert_response :success
    assert_not_includes response.body, "app.faylee.app"
    assert_not_includes policy_header, "app.faylee.app"
  end

  test "nothing loads inside a workspace when no site is configured" do
    Rails.configuration.x.stubs(:faylee_site_id).returns(nil)
    sign_in(users(:alice), @workspace)

    get dashboard_path

    assert_response :success
    assert_not_includes response.body, "app.faylee.app"
    assert_not_includes policy_header, "app.faylee.app"
  end

  private

  def policy_header
    response.headers["Content-Security-Policy-Report-Only"] || response.headers["Content-Security-Policy"]
  end
end
