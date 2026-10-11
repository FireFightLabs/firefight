require "test_helper"

# Test logins are credentials, so only admins manage them, and the password goes in and never comes back out.
class TestLoginsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    sign_in(users(:alice), @workspace)
  end

  test "the page lists each saved login with when its password was saved, and never the password" do
    save_login!(site_url: "https://shop.example.com", username: "halon-test@example.com", password: "hunter2-secret")

    get settings_test_logins_path, headers: inertia_headers

    login = inertia_props["testLogins"].sole
    assert_equal [ "shop.example.com", "https://shop.example.com", "halon-test@example.com" ], login.values_at("name", "siteUrl", "username")
    assert_match(/\APassword saved on /, login["passwordHint"])
    assert_not_includes response.body, "hunter2-secret"
  end

  test "adding a login keeps the password encrypted on its connection row and says so" do
    post test_logins_path, params: { site_url: "https://shop.example.com", login_url: "https://accounts.example.com/sign-in",
                                     username: "halon-test@example.com", password: "hunter2-secret", name: "Shop staging" }

    assert_redirected_to settings_test_logins_path
    assert_equal "Test login for shop.example.com was added.", flash[:notice]
    login = Integrations::SiteLogins.listed(@workspace).sole
    assert_equal [ "Shop staging", "https://accounts.example.com/sign-in" ], [ login.name, login.login_url ]
    assert_equal({ "username" => "halon-test@example.com", "password" => "hunter2-secret" }, Integrations::SiteLogins.secret_for(@workspace, login.id))
    stored = IntegrationEnvironment.find_by!(integration_id: login.id)
    assert_not_includes stored.read_attribute_before_type_cast(:credentials).to_s, "hunter2-secret"
  end

  test "a login that cannot be saved says why on its field" do
    post test_logins_path, params: { site_url: "ftp://shop.example.com", username: "", password: "" }

    assert_redirected_to settings_test_logins_path
    assert_empty Integrations::SiteLogins.listed(@workspace)
    errors = session[:inertia_errors].to_h.with_indifferent_access
    assert_equal "Site address must be an http or https address, such as https://shop.example.com.", errors[:site_url]
    assert_equal "Enter the test account's username.", errors[:username]
    assert_equal "Enter the test account's password.", errors[:password]
  end

  test "editing with the password left empty keeps the saved one and says so" do
    login = save_login!(site_url: "https://shop.example.com", username: "old@example.com", password: "kept-secret")

    patch test_login_path(login.id), params: { site_url: "https://shop.example.com", username: "new@example.com", password: "" }

    assert_equal "Test login for shop.example.com was updated.", flash[:notice]
    assert_equal({ "username" => "new@example.com", "password" => "kept-secret" }, Integrations::SiteLogins.secret_for(@workspace, login.id))
  end

  test "deleting a login removes its password with it and says so" do
    login = save_login!(site_url: "https://shop.example.com", username: "halon-test@example.com", password: "gone-secret")

    delete test_login_path(login.id)

    assert_equal "Test login for shop.example.com was deleted. Halon no longer signs in there.", flash[:notice]
    assert_empty Integrations::SiteLogins.listed(@workspace)
    assert_not IntegrationEnvironment.exists?(integration_id: login.id)
  end

  test "a member who is not an admin can neither see nor change test logins" do
    login = save_login!(site_url: "https://shop.example.com", username: "halon-test@example.com", password: "member-secret")
    sign_in(users(:bob), @workspace)

    get settings_test_logins_path, headers: inertia_headers
    assert_not_includes response.body, "shop.example.com"

    delete test_login_path(login.id)
    assert_equal 1, Integrations::SiteLogins.listed(@workspace).size
  end

  test "a test login is none of the workspace's connections on the Integrations page" do
    save_login!(site_url: "https://shop.example.com", username: "halon-test@example.com", password: "hidden-secret")

    get integrations_url, headers: inertia_headers

    assert_not_includes inertia_props["integrations"].map { |each| each["provider"] }, IntegrationProvider.test_logins.key
    assert_not_includes inertia_props["providers"].map { |each| each["key"] }, IntegrationProvider.test_logins.key
  end

  test "the Integrations page's connect endpoint never makes a test login" do
    post integrations_url, params: { provider: IntegrationProvider.test_logins.key, name: "Shop", credentials: { password: "x" } }

    assert_empty Integrations::SiteLogins.listed(@workspace)
  end

  private

  def save_login!(**attributes)
    Integration::SiteLogin.new(workspace: @workspace, **attributes).save!
  end
end
