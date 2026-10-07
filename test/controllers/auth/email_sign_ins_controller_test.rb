require "test_helper"

class Auth::EmailSignInsControllerTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    FeatureFlags.enable_globally!(FeatureFlags::SELF_SERVE_SIGNUP)
    @alice = users(:alice)
  end

  test "asking for a link sends it and says to check your email" do
    assert_enqueued_emails 1 do
      post email_sign_in_path, params: { email: " Alice@Example.com " }
    end

    assert_redirected_to email_sign_in_sent_path
    assert LoginToken.usable.exists?(email: "alice@example.com")

    get email_sign_in_sent_path, headers: inertia_headers
    assert_equal "alice@example.com", inertia_props["email"]
  end

  test "an address nobody holds gets the same answer and the same email" do
    assert_enqueued_emails 1 do
      post email_sign_in_path, params: { email: "nobody-here@example.com" }
    end

    assert_redirected_to email_sign_in_sent_path
  end

  test "an address that is not an email is sent back with an error" do
    assert_no_enqueued_emails do
      post email_sign_in_path, params: { email: "not an email" }
    end

    assert_redirected_to login_path
    assert_not LoginToken.exists?
  end

  test "the link points at this host's confirm page" do
    post email_sign_in_path, params: { email: @alice.email }

    job = enqueued_jobs.find { |enqueued| enqueued["job_class"] == "ActionMailer::MailDeliveryJob" }
    url = job["arguments"].last["args"].first["url"]
    assert_match %r{\Ahttp://www.example.com/auth/email/confirm\?token=}, url
  end

  test "opening the link shows a button and does not use it up" do
    token = LoginToken.issue!(email: @alice.email)

    get email_sign_in_link_path(token: token), headers: inertia_headers

    assert_equal "login/confirm-email", JSON.parse(response.body)["component"]
    assert inertia_props["usable"]
    assert LoginToken.find_usable(token)
    assert_nil session[:user_id]
  end

  test "opening a used link says it has expired" do
    token = LoginToken.issue!(email: @alice.email)
    LoginToken.consume(token)

    get email_sign_in_link_path(token: token), headers: inertia_headers

    assert_not inertia_props["usable"]
  end

  test "confirming signs the member in, keeps where they were going and starts a fresh session" do
    get settings_statuses_path
    token = LoginToken.issue!(email: @alice.email)

    post consume_email_sign_in_path, params: { token: token }

    assert_redirected_to settings_statuses_path
    assert_equal @alice.id, session[:user_id]
    assert_nil session[:return_to]
    assert UserIdentity.exists?(user: @alice, provider: UserIdentity::EMAIL, uid: @alice.email)
  end

  test "a link works once" do
    token = LoginToken.issue!(email: @alice.email)
    post consume_email_sign_in_path, params: { token: token }
    delete logout_path

    post consume_email_sign_in_path, params: { token: token }

    assert_redirected_to login_path
    assert_equal Auth::EmailSignInsController::EXPIRED_MESSAGE, flash[:alert]
    assert_nil session[:user_id]
  end

  test "an expired link signs nobody in" do
    token = LoginToken.issue!(email: @alice.email)

    travel LoginToken::LIFETIME + 1.minute do
      post consume_email_sign_in_path, params: { token: token }
    end

    assert_redirected_to login_path
    assert_nil session[:user_id]
  end

  test "using one link closes the other links sent to the same address" do
    older = LoginToken.issue!(email: @alice.email)
    newer = LoginToken.issue!(email: @alice.email)

    post consume_email_sign_in_path, params: { token: newer }
    delete logout_path
    post consume_email_sign_in_path, params: { token: older }

    assert_redirected_to login_path
    assert_nil session[:user_id]
  end

  test "an address nobody holds lands on the signup page" do
    token = LoginToken.issue!(email: "nobody-here@example.com")

    post consume_email_sign_in_path, params: { token: token }

    assert_redirected_to onboarding_signup_path
    assert_nil session[:user_id]
    assert_nil User.find_by(email: "nobody-here@example.com")
  end

  test "email sign-in is closed while self-serve sign-in is off" do
    FeatureFlags.disable_globally!(FeatureFlags::SELF_SERVE_SIGNUP)
    token = LoginToken.issue!(email: @alice.email)

    assert_no_enqueued_emails do
      post email_sign_in_path, params: { email: @alice.email }
    end
    assert_redirected_to login_path

    post consume_email_sign_in_path, params: { token: token }
    assert_redirected_to login_path
    assert_nil session[:user_id]
  end

  test "email sign-in is closed when this host cannot send mail" do
    MailDelivery.stubs(:configured?).returns(false)

    assert_no_enqueued_emails do
      post email_sign_in_path, params: { email: @alice.email }
    end
    assert_redirected_to login_path
  end
end
