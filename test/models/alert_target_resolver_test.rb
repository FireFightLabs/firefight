require "test_helper"

class AlertTargetResolverTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :catalog_types,
           :catalog_attribute_definitions, :catalog_entries, :catalog_entry_relationships

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @team = catalog_entries(:platform_team)
    @service_entry = catalog_entries(:auth_service)
  end

  def resolver(fields = { "service" => "auth_service" })
    Alert::TargetResolver.new(@workspace, fields)
  end

  test "owning_team invite resolves members plus manager, deduped" do
    other = @workspace.workspace_memberships.where.not(id: @alice.id).first
    @team.update_column(:attributes, { "manager" => @alice.id, "members" => [ @alice.id, other.id ] })

    memberships = resolver.memberships_for([ { "type" => "owning_team", "of" => "service" } ])

    assert_equal [ @alice, other ].map(&:id).sort, memberships.map(&:id).sort
  end

  test "explicit member target resolves, unknown member is a note" do
    r = resolver
    memberships = r.memberships_for([
      { "type" => "member", "member_id" => @alice.id },
      { "type" => "member", "member_id" => SecureRandom.uuid }
    ])

    assert_equal [ @alice ], memberships
    assert r.notes.any? { |n| n.include?("not found") }
  end

  test "owning_team notify prefers the service channel over the team channel" do
    @service_entry.update_column(:attributes, { "slack_channel" => "C_SERVICE" })
    @team.update_column(:attributes, { "slack_channel" => "C_TEAM" })

    assert_equal "C_SERVICE", resolver.channel_for({ "type" => "owning_team", "of" => "service" })
  end

  test "owning_team notify falls back to the team channel" do
    @team.update_column(:attributes, { "slack_channel" => "C_TEAM" })

    assert_equal "C_TEAM", resolver.channel_for({ "type" => "owning_team", "of" => "service" })
  end

  test "member notify resolves to the platform user id (DM)" do
    assert_equal @alice.platform_user_id, resolver.channel_for({ "type" => "member", "member_id" => @alice.id })
  end

  test "service missing from catalog notes the miss and resolves nothing" do
    r = resolver({ "service" => "ghost" })

    assert_empty r.memberships_for([ { "type" => "owning_team", "of" => "service" } ])
    assert r.notes.any? { |n| n.include?("not in the catalog") }
  end

  test "team without people notes the miss" do
    @team.update_column(:attributes, {})
    r = resolver

    assert_empty r.memberships_for([ { "type" => "owning_team", "of" => "service" } ])
    assert r.notes.any? { |n| n.include?("no members or manager") }
  end
end
