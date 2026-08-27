require "test_helper"

class AlertTargetResolverTest < ActiveSupport::TestCase
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

    memberships = resolver.memberships_for([ { "type" => PolicyRule::AlertRoutingOutcome::TARGET_OWNING_TEAM, "of" => "service" } ])

    assert_equal [ @alice, other ].map(&:id).sort, memberships.map(&:id).sort
  end

  test "explicit member target resolves, unknown member is a note" do
    r = resolver
    memberships = r.memberships_for([
      { "type" => PolicyRule::AlertRoutingOutcome::TARGET_MEMBER, "member_id" => @alice.id },
      { "type" => PolicyRule::AlertRoutingOutcome::TARGET_MEMBER, "member_id" => SecureRandom.uuid }
    ])

    assert_equal [ @alice ], memberships
    assert r.notes.any? { |n| n.include?("not found") }
  end

  test "owning_team notify prefers the service channel over the team channel" do
    @service_entry.update_column(:attributes, { "slack_channel" => "C_SERVICE" })
    @team.update_column(:attributes, { "slack_channel" => "C_TEAM" })

    assert_equal "C_SERVICE", resolver.channel_for({ "type" => PolicyRule::AlertRoutingOutcome::TARGET_OWNING_TEAM, "of" => "service" })
  end

  test "owning_team notify falls back to the team channel" do
    @team.update_column(:attributes, { "slack_channel" => "C_TEAM" })

    assert_equal "C_TEAM", resolver.channel_for({ "type" => PolicyRule::AlertRoutingOutcome::TARGET_OWNING_TEAM, "of" => "service" })
  end

  test "member notify resolves to the platform user id (DM)" do
    assert_equal @alice.platform_user_id, resolver.channel_for({ "type" => PolicyRule::AlertRoutingOutcome::TARGET_MEMBER, "member_id" => @alice.id })
  end

  test "service missing from catalog notes the miss and resolves nothing" do
    r = resolver({ "service" => "ghost" })

    assert_empty r.memberships_for([ { "type" => PolicyRule::AlertRoutingOutcome::TARGET_OWNING_TEAM, "of" => "service" } ])
    assert r.notes.any? { |n| n.include?("not in the catalog") }
  end

  test "explicit team target resolves members and channel" do
    other = @workspace.workspace_memberships.where.not(id: @alice.id).first
    @team.update_column(:attributes, { "manager" => @alice.id, "members" => [ other.id ], "slack_channel" => "C_TEAM" })
    r = resolver

    memberships = r.memberships_for([ { "type" => PolicyRule::AlertRoutingOutcome::TARGET_TEAM, "entry_id" => @team.id } ])

    assert_equal [ @alice, other ].map(&:id).sort, memberships.map(&:id).sort
    assert_equal "C_TEAM", r.channel_for({ "type" => PolicyRule::AlertRoutingOutcome::TARGET_TEAM, "entry_id" => @team.id })
  end

  test "unknown team entry is a note" do
    r = resolver

    assert_empty r.memberships_for([ { "type" => PolicyRule::AlertRoutingOutcome::TARGET_TEAM, "entry_id" => SecureRandom.uuid } ])
    assert r.notes.any? { |n| n.include?("not found") }
  end

  test "vanished team member references are noted" do
    @team.update_column(:attributes, { "members" => [ @alice.id, SecureRandom.uuid ] })
    r = resolver

    memberships = r.memberships_for([ { "type" => PolicyRule::AlertRoutingOutcome::TARGET_OWNING_TEAM, "of" => "service" } ])

    assert_equal [ @alice ], memberships
    assert r.notes.any? { |n| n.include?("no longer exist") }
  end

  test "team without people notes the miss" do
    @team.update_column(:attributes, {})
    r = resolver

    assert_empty r.memberships_for([ { "type" => PolicyRule::AlertRoutingOutcome::TARGET_OWNING_TEAM, "of" => "service" } ])
    assert r.notes.any? { |n| n.include?("no members or manager") }
  end

  test "resolution follows the role, not the attribute slug" do
    catalog_attribute_definitions(:team_members).update_column(:slug, "engineers")
    catalog_attribute_definitions(:team_slack_channel).update_column(:slug, "war_room")
    @team.update_column(:attributes, { "engineers" => [ @alice.id ], "war_room" => "C_WAR_ROOM" })
    r = resolver

    memberships = r.memberships_for([ { "type" => PolicyRule::AlertRoutingOutcome::TARGET_OWNING_TEAM, "of" => "service" } ])

    assert_equal [ @alice ], memberships
    assert_equal "C_WAR_ROOM", r.channel_for({ "type" => PolicyRule::AlertRoutingOutcome::TARGET_TEAM, "entry_id" => @team.id })
  end

  test "unmapped paging roles note the type gap, not the entry" do
    catalog_attribute_definitions(:team_members).update_column(:role, nil)
    catalog_attribute_definitions(:team_manager).update_column(:role, nil)
    @team.update_column(:attributes, { "members" => [ @alice.id ] })
    r = resolver

    assert_empty r.memberships_for([ { "type" => PolicyRule::AlertRoutingOutcome::TARGET_OWNING_TEAM, "of" => "service" } ])
    assert r.notes.any? { |n| n.include?("no attribute marked as Members or Manager") }
  end

  test "unmapped notification channel role notes the type gap" do
    catalog_attribute_definitions(:team_slack_channel).update_column(:role, nil)
    @team.update_column(:attributes, { "slack_channel" => "C_TEAM" })
    r = resolver

    assert_nil r.channel_for({ "type" => PolicyRule::AlertRoutingOutcome::TARGET_TEAM, "entry_id" => @team.id })
    assert r.notes.any? { |n| n.include?("no attribute marked as Notification channel") }
  end
end
