require "test_helper"

class Integration::SiteLoginTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
  end

  test "a login is kept on a connection row that mints no packs and is none of the workspace's connections" do
    login = save!(site_url: "https://shop.example.com/", username: "halon@example.com", password: "secret-one")

    integration = login.integration
    assert integration.test_login?
    assert_empty Ability::Role.where(integration_id: integration.id)
    assert_not_includes @workspace.integrations.active, integration
    assert_not_includes @workspace.integrations.connections, integration
    assert_equal "shop.example.com", integration.name
  end

  test "the site and login addresses must be http or https, hold no credentials, and the login page must be on the site" do
    refused = build(site_url: "shop.example.com", username: "a", password: "b")
    assert_not refused.valid?
    assert_equal [ "Site address must be an http or https address, such as https://shop.example.com." ], refused.errors[:site_url]

    with_userinfo = build(site_url: "https://user:pass@shop.example.com", username: "a", password: "b")
    assert_not with_userinfo.valid?
    assert_equal [ "Site address cannot hold a username or password. Put them in their own fields." ], with_userinfo.errors[:site_url]

    elsewhere = build(site_url: "https://shop.example.com", login_url: "https://evil.example.org/login", username: "a", password: "b")
    assert_not elsewhere.valid?
    assert_equal [ "Login page must be on the same site as shop.example.com." ], elsewhere.errors[:login_url]

    assert build(site_url: "https://shop.example.co.uk", login_url: "https://accounts.example.co.uk/in", username: "a", password: "b").valid?
    assert_not build(site_url: "https://shop.example.co.uk", login_url: "https://other.co.uk/in", username: "a", password: "b").valid?
  end

  test "one login per site, www or not" do
    save!(site_url: "https://shop.example.com", username: "a", password: "b")

    second = build(site_url: "https://WWW.shop.example.com/login", username: "c", password: "d")
    error = assert_raises(ActiveModel::ValidationError) { second.save! }
    assert_equal [ "A test login for shop.example.com is already saved. Edit that one instead." ], error.model.errors[:site_url]
  end

  test "editing keeps the saved password when none is typed, and a new password moves when it was saved" do
    login = save!(site_url: "https://shop.example.com", username: "a", password: "first")
    first_saved = login.password_set_at

    travel 2.days do
      found = Integration::SiteLogin.find_in!(@workspace, login.id)
      found.assign_attributes(username: "b", password: "")
      found.save!
      assert_equal first_saved.to_i, Integration::SiteLogin.find_in!(@workspace, login.id).password_set_at.to_i

      found.assign_attributes(password: "second")
      found.save!
      assert_operator Integration::SiteLogin.find_in!(@workspace, login.id).password_set_at, :>, first_saved
    end
    assert_equal({ "username" => "b", "password" => "second" }, Integrations::SiteLogins.secret_for(@workspace, login.id))
  end

  private

  def build(**attributes) = Integration::SiteLogin.new(workspace: @workspace, **attributes)

  def save!(**attributes) = build(**attributes).save!
end
