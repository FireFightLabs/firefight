require "test_helper"

class CatalogEntryRepositoryTest < ActiveSupport::TestCase
  setup do
    catalog_types(:service_ws1).catalog_attribute_definitions.create!(
      name: "Code", slug: "code", attribute_type: CatalogAttributeDefinition::TYPE_TEXT,
      role: CatalogAttributeDefinition::ROLE_REPOSITORY, position: 9
    )
    @service = catalog_entries(:auth_service)
  end

  test "the repository is read from whichever attribute carries the role, however it was typed" do
    {
      "acme/auth" => "acme/auth",
      "https://github.com/acme/auth" => "acme/auth",
      "https://github.com/acme/auth.git" => "acme/auth",
      "git@github.com:acme/auth.git" => "acme/auth",
      "https://gitlab.com/acme/auth/" => "acme/auth"
    }.each do |typed, expected|
      @service.update!(attributes: { "code" => typed })
      assert_equal expected, @service.reload.repository, typed
    end
  end

  test "something that is not a repository gives none rather than a wrong one" do
    @service.update!(attributes: { "code" => "the auth thing" })

    assert_nil @service.reload.repository
  end

  test "the services a repository belongs to are found in any case, and a high risk pull request goes to their channel" do
    @service.update!(attributes: { "code" => "https://github.com/Acme/Auth", "slack_channel" => "C-AUTH" })
    CatalogEntry.create!(workspace: @service.workspace, catalog_type: @service.catalog_type, name: "Payments", slug: "payments", attributes: { "code" => "acme/payments" })

    assert_equal [ @service ], CatalogEntry.owning_repository(workspaces(:slack_workspace_one), "acme/auth")
    assert_equal "C-AUTH", @service.review_alert_channel

    @service.update!(review_alerts: false)
    assert_nil @service.review_alert_channel
  end
end
