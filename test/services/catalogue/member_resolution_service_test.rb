require "test_helper"

class Catalogue::MemberResolutionServiceTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @membership = workspace_memberships(:alice_workspace_one)
    @team_type = catalog_types(:team_ws1)
    @service = Catalogue::MemberResolutionService.new(@workspace)
  end

  test "resolves the members held by entries' member attributes" do
    @team_type.catalog_attribute_definitions.create!(
      slug: "team_lead", name: "Team Lead",
      attribute_type: CatalogAttributeDefinition::TYPE_WORKSPACE_MEMBER,
      required: false, position: 10, config: {}
    )
    entry = catalog_entries(:platform_team)
    entry.update!(attributes: entry.entry_attributes.merge("team_lead" => @membership.id))

    resolved = @service.resolve_for_entries([ entry ], @team_type.reload)

    assert_equal [ @membership.id ], resolved.map { |member| member[:id] }
    assert_equal @membership.display_name, resolved.first[:name]
  end

  test "a type without member attributes resolves to nothing" do
    assert_equal [], @service.resolve_for_entries([ catalog_entries(:platform_team) ], @team_type)
  end
end
