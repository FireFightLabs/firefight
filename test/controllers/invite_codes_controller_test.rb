require "test_helper"

class InviteCodesControllerTest < ActionDispatch::IntegrationTest
  fixtures :users, :invite_codes

  test "create stores invite code in session when code is valid" do
    post claim_invite_code_path, params: { code: "BETA-ACCESS" }

    assert_redirected_to login_path
    assert_equal "Invite code accepted. You can continue with Slack.", flash[:notice]
    assert_equal invite_codes(:active_public_beta_code).id, session[:invite_code_id]
  end

  test "create clears session when code is invalid" do
    post claim_invite_code_path, params: { code: "BETA-ACCESS" }
    assert_equal invite_codes(:active_public_beta_code).id, session[:invite_code_id]

    post claim_invite_code_path, params: { code: "NOT-A-CODE" }

    assert_redirected_to login_path
    assert_equal "That invite code is invalid or expired.", flash[:alert]
    assert_nil session[:invite_code_id]
  end
end
