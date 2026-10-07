require "test_helper"
require "open3"

class FayleeControllerTest < ActionDispatch::IntegrationTest
  setup do
    @previous_token = ENV["FAYLEE_VERIFICATION_TOKEN"]
    @previous_site_id = ENV["FAYLEE_SITE_ID"]
  end

  teardown do
    ENV["FAYLEE_VERIFICATION_TOKEN"] = @previous_token
    ENV["FAYLEE_SITE_ID"] = @previous_site_id
  end

  test "verification returns the configured token without authentication" do
    ENV["FAYLEE_VERIFICATION_TOKEN"] = "test-verification-token"

    get "/.well-known/faylee-verification.txt"

    assert_response :success
    assert_equal "test-verification-token", response.body
    assert_equal "text/plain; charset=utf-8", response.media_type
  end

  test "verification is not found when no token is configured" do
    ENV["FAYLEE_VERIFICATION_TOKEN"] = nil

    get "/.well-known/faylee-verification.txt"

    assert_response :not_found
    assert_nil response.headers["Location"]
  end

  test "the widget is absent when no site is configured" do
    ENV["FAYLEE_SITE_ID"] = nil

    get login_path

    assert_response :success
    assert_not_includes response.body, "https://app.faylee.app/widget.js"
  end

  test "the widget includes the configured site and CSP nonce" do
    ENV["FAYLEE_SITE_ID"] = "test-site-id"

    get login_path

    assert_response :success
    assert_match(%r{<script[^>]+src="https://app\.faylee\.app/widget\.js"[^>]+data-site="test-site-id"[^>]+async[^>]+nonce="([^"]+)"[^>]*></script>}, response.body)
    assert_equal Regexp.last_match(1), response.body[/<meta name="csp-nonce" content="([^"]+)"/, 1]
  end

  test "CSP does not allow Faylee when the widget is disabled" do
    output = content_security_policy_for(site_id: nil)

    assert_includes output, "script-src 'self'"
    assert_not_includes output, "https://app.faylee.app"
  end

  test "CSP allows Faylee sources when the widget is enabled" do
    output = content_security_policy_for(site_id: "test-site-id")

    assert_match(/script-src[^;]*https:\/\/app\.faylee\.app/, output)
    assert_match(/connect-src[^;]*https:\/\/app\.faylee\.app/, output)
    assert_match(/frame-src[^;]*https:\/\/app\.faylee\.app/, output)
  end

  private

  def content_security_policy_for(site_id:)
    environment = { "FAYLEE_SITE_ID" => site_id, "SLACK_SIGNING_SECRET" => "test-secret" }
    command = <<~RUBY
      require "./config/environment"
      puts Rails.application.config.content_security_policy.build(nil)
    RUBY
    output, status = Open3.capture2e(environment, RbConfig.ruby, "-e", command)
    assert_predicate status, :success?, output
    output
  end
end
