require "application_system_test_case"

class OperatorConsoleTest < ApplicationSystemTestCase
  setup do
    @user = users(:alice)
    @previous = ENV[Operator::Credential::OPERATOR_IDS_ENV]
    ENV[Operator::Credential::OPERATOR_IDS_ENV] = @user.id
    sign_in(@user, workspaces(:slack_workspace_one))
  end

  teardown do
    ENV[Operator::Credential::OPERATOR_IDS_ENV] = @previous
  end

  test "an operator sets up an authenticator, keeps the recovery codes, and is asked for a code next time" do
    visit operator_root_path

    assert_text "Set up your authenticator"
    assert_selector "svg[role=img]"
    page.save_screenshot(Rails.root.join("tmp/screenshots/operator-setup.png"))
    fill_in "Code from the app", with: "000000"
    click_button "Confirm and continue"
    assert_text Operator::Credential::WRONG_MESSAGE

    fill_in "Code from the app", with: ROTP::TOTP.new(Operator::Credential.for(@user).totp_secret).now
    click_button "Confirm and continue"

    assert_text "Save your recovery codes"
    assert_selector "ol li", count: Operator::Credential::RECOVERY_CODE_COUNT
    page.save_screenshot(Rails.root.join("tmp/screenshots/operator-recovery-codes.png"))
  end

  # Past the code is Flightdeck, which cannot draw without Solid Queue's tables, so the controller test covers the rest.
  test "an operator who set up before is asked for a code, and told a recovery code works too" do
    Operator::Credential.start_for!(@user).confirm!(ROTP::TOTP.new(Operator::Credential.for(@user).totp_secret).now)

    visit operator_root_path

    assert_text "Enter your code"
    assert_text "You have #{Operator::Credential::RECOVERY_CODE_COUNT} left."
    page.save_screenshot(Rails.root.join("tmp/screenshots/operator-verify.png"))
  end
end
