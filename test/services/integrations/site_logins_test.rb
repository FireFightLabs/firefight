require "test_helper"

module Integrations
  class SiteLoginsTest < ActiveSupport::TestCase
    setup do
      @workspace = workspaces(:slack_workspace_one)
      @shop = Integration::SiteLogin.new(workspace: @workspace, site_url: "https://shop.example.com", username: "halon@example.com",
                                         password: "only-for-the-box", name: "Shop").save!
      Integration::SiteLogin.new(workspace: @workspace, site_url: "https://admin.example.com", username: "ops@example.com", password: "x").save!
    end

    test "listed logins carry no password, in name order" do
      listed = SiteLogins.listed(@workspace)

      assert_equal [ "admin.example.com", "Shop" ], listed.map(&:name)
      assert_equal %i[id name site_url login_url username password_hint], SiteLogins::Login.members
      assert listed.none? { |login| login.to_h.values.include?("only-for-the-box") }
    end

    test "an address finds the login of its site by host, whatever its case, path or leading www" do
      assert_equal @shop.id, SiteLogins.for_url(@workspace, "https://WWW.Shop.example.com/checkout?step=2").id
      assert_nil SiteLogins.for_url(@workspace, "https://example.com/")
      assert_nil SiteLogins.for_url(@workspace, "not an address")
      assert_nil SiteLogins.for_url(workspaces(:slack_workspace_two), "https://shop.example.com")
    end

    test "the secret is read for one login of the workspace, and none for another workspace's or a deleted one" do
      assert_equal({ "username" => "halon@example.com", "password" => "only-for-the-box" }, SiteLogins.secret_for(@workspace, @shop.id))
      assert_nil SiteLogins.secret_for(workspaces(:slack_workspace_two), @shop.id)

      @shop.destroy!
      assert_nil SiteLogins.secret_for(@workspace, @shop.id)
    end
  end
end
