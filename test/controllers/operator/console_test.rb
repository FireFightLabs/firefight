require "test_helper"

class Operator::ConsoleTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:alice)
    @previous = ENV[Operator::Credential::OPERATOR_IDS_ENV]
    ENV[Operator::Credential::OPERATOR_IDS_ENV] = @user.id
  end

  teardown do
    ENV[Operator::Credential::OPERATOR_IDS_ENV] = @previous
  end

  test "anyone who is not an operator gets not found everywhere in the console, the jobs dashboard included" do
    sign_in(users(:bob), workspaces(:slack_workspace_one))

    [ routes.operator_root_path, routes.operator_setup_path, routes.operator_verify_path, "#{routes.operator_jobs_path}/" ].each do |path|
      get path
      assert_response :not_found, path
    end
    post routes.operator_verify_path, params: { code: "123456" }
    assert_response :not_found
  end

  test "someone signed out gets not found too" do
    get routes.operator_root_path

    assert_response :not_found
  end

  test "an operator without an authenticator is sent to set one up, and then straight into the console" do
    sign_in(@user, workspaces(:slack_workspace_one))

    get routes.operator_root_path
    assert_redirected_to routes.operator_setup_path

    get routes.operator_setup_path, headers: inertia_headers
    assert inertia_props["qr"].is_a?(Array)

    post routes.operator_setup_path, params: { code: code_for(@user) }, headers: inertia_headers
    assert_equal Operator::Credential::RECOVERY_CODE_COUNT, inertia_props["codes"].size

    get routes.operator_root_path, headers: inertia_headers
    assert_equal "operator/overview", JSON.parse(response.body)["component"]
  end

  test "an operator is asked for a code before the jobs dashboard, and a wrong one says so" do
    sign_in(@user, workspaces(:slack_workspace_one))
    credential = Operator::Credential.start_for!(@user)
    credential.confirm!(code_for(@user))

    get "#{routes.operator_jobs_path}/"
    assert_redirected_to routes.operator_verify_path

    post routes.operator_verify_path, params: { code: "000000" }
    assert_redirected_to routes.operator_verify_path

    travel 31.seconds do
      post routes.operator_verify_path, params: { code: code_for(@user) }
      assert_redirected_to "#{routes.operator_jobs_path}/"
    end
  end

  test "a correct code from the page loads the console whole, since Flightdeck is not an Inertia page" do
    sign_in(@user, workspaces(:slack_workspace_one))
    Operator::Credential.start_for!(@user).confirm!(code_for(@user))

    travel 31.seconds do
      post routes.operator_verify_path, params: { code: code_for(@user) }, headers: inertia_headers
    end

    assert_response :conflict
    assert_equal routes.operator_root_path, URI(response.headers["X-Inertia-Location"]).path
  end

  # The test database has no Solid Queue tables, so Flightdeck's pages cannot draw here. What matters is that every one
  # of them runs the console's checks, which the redirect above shows for a real request.
  test "every Flightdeck page inherits the console's checks" do
    assert_includes Flightdeck::ApplicationController.ancestors, Operator::BaseController
  end

  test "a verified console asks again once the window runs out" do
    sign_in(@user, workspaces(:slack_workspace_one))
    Operator::Credential.start_for!(@user).confirm!(code_for(@user))
    travel 31.seconds do
      post routes.operator_verify_path, params: { code: code_for(@user) }
    end

    travel Operator::Credential::VERIFIED_FOR + 1.minute do
      get routes.operator_root_path
      assert_redirected_to routes.operator_verify_path
    end
  end

  private

  # After a request into Flightdeck the test's own helpers carry its prefix, so the app's routes are named directly.
  def routes = Rails.application.routes.url_helpers

  def code_for(user) = ROTP::TOTP.new(Operator::Credential.for(user).totp_secret).now
end
