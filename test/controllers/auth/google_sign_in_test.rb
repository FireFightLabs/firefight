require "test_helper"

class Auth::GoogleSignInTest < ActionDispatch::IntegrationTest
  setup do
    FeatureFlags.enable_globally!(FeatureFlags::SELF_SERVE_SIGNUP)
    @configured = Rails.application.config.x.google_sign_in
    Rails.application.config.x.google_sign_in = true
    @alice = users(:alice)
  end

  teardown do
    Rails.application.config.x.google_sign_in = @configured
  end

  test "a verified Google account signs a member in and keeps the page they were going to" do
    get settings_statuses_path
    google_callback(email: @alice.email)

    assert_redirected_to settings_statuses_path
    assert_equal @alice.id, session[:user_id]
    assert_equal workspace_memberships(:alice_workspace_one).workspace_id, session[:workspace_id]
    assert UserIdentity.exists?(user: @alice, provider: UserIdentity::GOOGLE)
  end

  test "a Google account whose email Google has not verified is refused" do
    google_callback(email: @alice.email, verified: false)

    assert_redirected_to login_path
    assert_equal Auth::OmniauthCallbacksController::GOOGLE_UNVERIFIED_MESSAGE, flash[:alert]
    assert_nil session[:user_id]
    assert_not UserIdentity.exists?(user: @alice, provider: UserIdentity::GOOGLE)
  end

  test "a Google account nobody holds lands on the signup page without making anyone" do
    google_callback(email: "newcomer@example.com")

    assert_redirected_to onboarding_signup_path
    assert_nil session[:user_id]
    assert_nil User.find_by(email: "newcomer@example.com")
  end

  test "a person with no workspace lands on the signup page" do
    loner = User.create!(email: "loner@example.com", name: "Loner")

    google_callback(email: loner.email)

    assert_redirected_to onboarding_signup_path
    assert_nil session[:user_id]
  end

  test "Google is refused while self-serve sign-in is off" do
    FeatureFlags.disable_globally!(FeatureFlags::SELF_SERVE_SIGNUP)

    google_callback(email: @alice.email)

    assert_redirected_to login_path
    assert_equal Auth::OmniauthCallbacksController::UNAVAILABLE_MESSAGE, flash[:alert]
    assert_nil session[:user_id]
  end

  test "Google is refused when this host has no Google app" do
    Rails.application.config.x.google_sign_in = false

    google_callback(email: @alice.email)

    assert_redirected_to login_path
    assert_nil session[:user_id]
  end

  private

  def google_callback(email:, verified: true)
    auth = mock_google_auth_hash(info: { email: verified ? email : nil, unverified_email: email, email_verified: verified })
    get google_callback_path, env: { "omniauth.auth" => auth }
  end
end
