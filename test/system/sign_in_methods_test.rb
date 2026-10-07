require "application_system_test_case"

class SignInMethodsTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  setup do
    @google_configured = Rails.application.config.x.google_sign_in
    Rails.application.config.x.google_sign_in = true
    @alice = users(:alice)
  end

  teardown do
    Rails.application.config.x.google_sign_in = @google_configured
  end

  test "the sign-in page offers only Slack while self-serve sign-in is off" do
    visit login_path

    assert_link "Continue with Slack"
    assert_no_link "Continue with Google"
    assert_no_field "Email"
    page.save_screenshot(Rails.root.join("tmp/screenshots/sign-in-slack-only.png"))
  end

  test "a member signs in with an emailed link" do
    FeatureFlags.enable_globally!(FeatureFlags::SELF_SERVE_SIGNUP)
    visit login_path

    assert_link "Continue with Slack"
    assert_link "Continue with Google"
    page.save_screenshot(Rails.root.join("tmp/screenshots/sign-in-all-methods.png"))

    perform_enqueued_jobs do
      fill_in "Email", with: @alice.email
      click_on "Email me a sign-in link"
      assert_text "Check your email"
    end
    assert_text @alice.email
    page.save_screenshot(Rails.root.join("tmp/screenshots/sign-in-check-email.png"))

    link = ActionMailer::Base.deliveries.last.text_part.body.to_s[%r{https?://\S+/auth/email/confirm\?token=\S+}]
    visit link
    assert_text "Finish signing in"
    page.save_screenshot(Rails.root.join("tmp/screenshots/sign-in-confirm.png"))

    click_on "Sign in"
    assert_current_path dashboard_path

    visit link
    assert_text "This link has expired"
    page.save_screenshot(Rails.root.join("tmp/screenshots/sign-in-link-expired.png"))
  end

  test "asking for too many links shows why under the email field" do
    FeatureFlags.enable_globally!(FeatureFlags::SELF_SERVE_SIGNUP)
    store = Rack::Attack.cache.store
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

    6.times do
      visit login_path
      fill_in "Email", with: @alice.email
      click_on "Email me a sign-in link"
      assert_text(/Check your email|Too many sign-in links/)
    end

    assert_text "Too many sign-in links were asked for. Wait a little, then try again."
    assert_current_path login_path
    page.save_screenshot(Rails.root.join("tmp/screenshots/sign-in-too-many.png"))
  ensure
    Rack::Attack.cache.store = store
  end

  test "an address with no workspace lands on the signup page" do
    FeatureFlags.enable_globally!(FeatureFlags::SELF_SERVE_SIGNUP)
    token = LoginToken.issue!(email: "newcomer@example.com")

    visit email_sign_in_link_path(token: token)
    click_on "Sign in"

    assert_text "Signup is coming soon"
    page.save_screenshot(Rails.root.join("tmp/screenshots/sign-in-signup-soon.png"))
  end

  test "a person removes a sign-in method from their profile, and the last one stays" do
    sign_in(@alice, workspaces(:slack_workspace_one))
    @alice.identities.create!(provider: UserIdentity::SLACK, uid: "T12345678/U12345678", email: @alice.email, last_used_at: 1.day.ago)
    @alice.identities.create!(provider: UserIdentity::GOOGLE, uid: "google-alice", email: @alice.email)

    visit dashboard_path
    find("[data-sidebar='menu-button']", text: @alice.name).click
    click_on "Profile"

    assert_text "Sign-in methods"
    page.save_screenshot(Rails.root.join("tmp/screenshots/profile-sign-in-methods.png"))

    within(:xpath, "//p[text()='Google']/ancestor::div[contains(@class,'rounded-md')][1]") { click_on "Remove" }
    assert_text "Remove Google?"
    page.save_screenshot(Rails.root.join("tmp/screenshots/profile-remove-confirm.png"))
    within("[role='dialog']") { click_on "Remove" }

    assert_text "Google (alice@example.com) was removed from your sign-in methods."
    assert_no_text "google-alice"
    assert_button "Remove", disabled: true
    find_button("Remove", disabled: true).find(:xpath, "..").hover
    assert_text UserIdentity::LAST_METHOD_REASON
    page.save_screenshot(Rails.root.join("tmp/screenshots/profile-last-method.png"))
  end
end
