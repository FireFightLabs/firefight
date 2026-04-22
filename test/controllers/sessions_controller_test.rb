require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  fixtures :invite_codes

  test "login clears expired claimed invite code from the session" do
    post claim_invite_code_path, params: { code: "BETA-ACCESS" }
    assert_equal invite_codes(:active_public_beta_code).id, session[:invite_code_id]

    invite_codes(:active_public_beta_code).update!(expires_at: 1.minute.ago)

    get login_path, headers: {
      "X-Inertia" => "true",
      "X-Inertia-Version" => InertiaRails.configuration.version
    }

    assert_response :success
    assert_match '"inviteCodeClaimed":false', response.body
    assert_nil session[:invite_code_id]
  end
end
