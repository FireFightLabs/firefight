require "test_helper"

# A sign-in or an install starts only from a form Firefight drew, posted with its token, so a link or an image on
# another site can never start one in someone's browser.
class Auth::OmniauthRequestPhaseTest < ActionDispatch::IntegrationTest
  setup do
    OmniAuth.config.test_mode = true
  end

  teardown do
    OmniAuth.config.test_mode = false
  end

  test "following a link to a sign-in or an install starts nothing and lands on the sign-in page" do
    [ sign_in_with_slack_path, install_slack_app_path, sign_in_with_google_path ].each do |path|
      get path

      assert_redirected_to "/login", "#{path} must not start a sign-in on GET"
    end
  end

  test "a form posted to a sign-in starts it" do
    post sign_in_with_slack_path

    assert_redirected_to "/auth/slack_openid/callback"
  end

  test "OmniAuth takes only posts" do
    assert_equal [ :post ], OmniAuth.config.allowed_request_methods
  end
end
