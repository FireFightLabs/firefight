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
end
