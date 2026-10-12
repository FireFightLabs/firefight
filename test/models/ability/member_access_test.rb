require "test_helper"

# Who can do what: each connection's read and changes pack is set to everyone, nobody or chosen people, through the pack's
# every_member flag and ordinary grants of it, the same rows the Permissions screen gives and takes away.
class Ability::MemberAccessTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @admin = workspace_memberships(:alice_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    @charlie = @workspace.workspace_memberships.create!(user: users(:charlie), role: :member, joined_at: Time.current)
    @northflank = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Faylee")
    @list = @northflank.tools.create!(name: "list_services", read_only: true, enabled: true).ability_action
    @restart = @northflank.tools.create!(name: "restart_service", read_only: false, enabled: true).ability_action
    @read = @northflank.permission_packs.find_by!(pack: Ability::Role::PACK_READ)
    @changes = @northflank.permission_packs.find_by!(pack: Ability::Role::PACK_CHANGES)
  end

  test "a connection starts as members reading it and nobody changing it, as before" do
    assert @read.every_member?
    assert_not @changes.every_member?
    assert @bob.permitted_to?(@list, @workspace)
    assert_not @bob.permitted_to?(@restart, @workspace)

    connection = row
    assert_equal Ability::Role::EVERYONE, connection.read.choice
    assert_equal Ability::Role::NOBODY, connection.change.choice
  end

  test "Nobody can read takes the read away from every member, including one who joins later, and admins keep it" do
    Ability::Grant.grant!(workspace: @workspace, principal: @bob, target: { role: @read })

    @read.let_members!(Ability::Role::NOBODY, by: @admin)

    assert_not @read.reload.every_member?
    assert_not @read.grants.exists?(principal: @bob)
    assert_not @bob.permitted_to?(@list, @workspace)
    assert_not newcomer.permitted_to?(@list, @workspace)
    assert @admin.permitted_to?(@list, @workspace)
    assert_equal Ability::Role::NOBODY, row.read.choice
  end

  test "Everyone can read gives the default back and clears a member's No access" do
    @read.let_members!(Ability::Role::NOBODY)
    @read.let_members!(Ability::Role::EVERYONE)
    Ability::Grant.withhold!(workspace: @workspace, principal: @bob, role: @read)
    assert_equal [ @bob.id ], row.read.left_out_ids

    @read.let_members!(Ability::Role::EVERYONE)

    assert @read.reload.every_member?
    assert_not @read.grants.exists?(principal: @bob)
    assert @bob.permitted_to?(@list, @workspace)
    assert @charlie.permitted_to?(@list, @workspace)
    assert_equal [], row.read.left_out_ids
  end

  test "choosing who can read grants the read pack to them and takes it from everyone else" do
    Ability::Grant.withhold!(workspace: @workspace, principal: @bob, role: @read)

    @read.let_members!(Ability::Role::CHOSEN, people: [ @bob ], by: @admin)

    grant = @read.grants.find_by!(principal: @bob)
    assert_not grant.no_access?
    assert_equal @admin, grant.granted_by
    assert @bob.permitted_to?(@list, @workspace)
    assert_not @charlie.permitted_to?(@list, @workspace)
    assert_not newcomer.permitted_to?(@list, @workspace)
    assert_equal Ability::Role::CHOSEN, row.read.choice
    assert_equal [ @bob.id ], row.read.people_ids
  end

  test "choosing again keeps a chosen member's narrower grant and revokes whoever is left out" do
    production = catalog_entries(:production_env).id
    Ability::Grant.grant!(workspace: @workspace, principal: @bob, target: { role: @read }, environment_ids: [ production ])
    @read.let_members!(Ability::Role::CHOSEN, people: [ @bob, @charlie ])

    assert_equal [ production ], @read.grants.find_by!(principal: @bob).environment_ids

    @read.let_members!(Ability::Role::CHOSEN, people: [ @charlie ])

    assert_not @read.grants.exists?(principal: @bob)
    assert @read.grants.exists?(principal: @charlie)
  end

  test "Everyone can change lets every member change it, including one who joins later, with no grant each" do
    @changes.let_members!(Ability::Role::EVERYONE, by: @admin)

    assert @changes.reload.every_member?
    assert_not @changes.grants.exists?
    assert @bob.permitted_to?(@restart, @workspace)
    assert newcomer.permitted_to?(@restart, @workspace)
    assert_not api_keys(:read_only_key).permitted_to?(@restart, @workspace)
    assert_equal Ability::Role::EVERYONE, row.change.choice
  end

  test "a tool added later to a pack every member changes reaches them at once" do
    @changes.let_members!(Ability::Role::EVERYONE)
    assert @bob.permitted_to?(@restart, @workspace)

    scale = @northflank.tools.create!(name: "scale_service", read_only: false, enabled: true).ability_action

    assert @bob.permitted_to?(scale, @workspace)
  end

  test "Nobody can change revokes every member's grant of the changes pack and leaves a service key's" do
    @changes.let_members!(Ability::Role::EVERYONE)
    Ability::Grant.grant!(workspace: @workspace, principal: @bob, target: { role: @changes })
    Ability::Grant.grant!(workspace: @workspace, principal: api_keys(:read_only_key), target: { role: @changes })

    @changes.let_members!(Ability::Role::NOBODY)

    assert_not @changes.reload.every_member?
    assert_not @changes.grants.exists?(principal: @bob)
    assert @changes.grants.exists?(principal: api_keys(:read_only_key))
    assert_not @bob.permitted_to?(@restart, @workspace)
    assert_equal Ability::Role::NOBODY, row.change.choice
  end

  test "choosing who can change grants the changes pack to them alone" do
    @changes.let_members!(Ability::Role::CHOSEN, people: [ @charlie ], by: @admin)

    assert @charlie.permitted_to?(@restart, @workspace)
    assert_not @bob.permitted_to?(@restart, @workspace)
    assert_not newcomer.permitted_to?(@restart, @workspace)
    assert_equal [ @charlie.id ], row.change.people_ids
  end

  test "Everyone can change answers the members waiting for that pack" do
    request = Ability::PackRequest.for!(@bob, @changes)
    request.update_columns(requested_at: Time.current)

    assert_enqueued_with(job: PackRequestSettledJob, args: [ request.id ]) do
      @changes.let_members!(Ability::Role::EVERYONE, by: @admin)
    end

    assert request.reload.given_at
    assert_equal @admin.id, request.given_by_id
  end

  test "each refusal says why" do
    assert_equal "Pick at least one person, or choose Nobody.", @read.member_access_blocked_reason(Ability::Role::CHOSEN, [])
    assert_equal "Admins can always do everything, so pick members only.",
                 @changes.member_access_blocked_reason(Ability::Role::CHOSEN, [ @admin ])
    assert_equal "Choose Everyone, Nobody or the people who can change Faylee (Northflank).",
                 @changes.member_access_blocked_reason("sometimes")
    assert_equal "Only a connection's read or changes pack is chosen for every member.",
                 @northflank.permission_packs.find_by!(pack: Ability::Role::PACK_EVERYTHING).member_access_blocked_reason(Ability::Role::EVERYONE)

    refused = assert_raises(ActiveRecord::RecordInvalid) { @changes.let_members!(Ability::Role::CHOSEN, people: []) }
    assert_includes refused.record.errors[:base], "Pick at least one person, or choose Nobody."
  end

  test "a connection with nothing that changes says so instead of offering a choice" do
    readonly = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Mirror")
    readonly.tools.create!(name: "list_services", read_only: true, enabled: true)
    changes = readonly.permission_packs.find_by!(pack: Ability::Role::PACK_CHANGES)

    assert_equal "Mirror (Northflank) has no tools that change anything.", changes.member_access_unavailable_reason
    assert_equal "Mirror (Northflank) has no tools that change anything.", changes.member_access_blocked_reason(Ability::Role::EVERYONE)
    assert_nil readonly.permission_packs.find_by!(pack: Ability::Role::PACK_READ).member_access_unavailable_reason
  end

  test "a read pack members no longer read by default cannot be withheld from one of them" do
    @read.let_members!(Ability::Role::NOBODY)

    refused = assert_raises(ActiveRecord::RecordInvalid) { Ability::Grant.withhold!(workspace: @workspace, principal: @bob, role: @read.reload) }
    assert_includes refused.record.errors[:base], Ability::Grant::NO_ACCESS_ONLY_FOR_DEFAULTS
    assert_not_includes @bob.reload.default_access.filter_map(&:role), @read
  end

  test "only a connection's read or changes pack can be held by every member" do
    set = @workspace.ability_roles.create!(name: "Database read-only")

    assert_not set.update(every_member: true)
  end

  test "a second connection of the same provider gets its own row, named as its packs are" do
    other = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Staging")
    other.tools.create!(name: "list_services", read_only: true, enabled: true)

    rows = Ability::Role.member_access_of(@workspace).connections

    assert_equal [ "Faylee (Northflank)", "Staging (Northflank)" ], rows.map { |connection| connection.integration.display_name }
    assert_not_equal rows.first.read.role, rows.second.read.role
  end

  test "a disconnected connection has no row, and the members to choose from leave out admins" do
    overview = Ability::Role.member_access_of(@workspace)
    assert_equal [ @bob, @charlie ].sort_by(&:display_name), overview.members
    assert_equal 3, overview.people_count

    @northflank.update!(deleted_at: Time.current)

    assert_empty Ability::Role.member_access_of(@workspace).connections
  end

  test "each notice names the connection and who" do
    assert_equal "Members can no longer read Faylee (Northflank).", @read.member_access_notice(Ability::Role::NOBODY)
    assert_equal "Members can change Faylee (Northflank).", @changes.member_access_notice(Ability::Role::EVERYONE)
    assert_equal "Bob Jones and Charlie Brown can change Faylee (Northflank).",
                 @changes.member_access_notice(Ability::Role::CHOSEN, [ @bob, @charlie ])
  end

  private

  def row = Ability::Role.member_access_of(@workspace).connections.find { |connection| connection.integration == @northflank }

  def newcomer
    user = User.create!(email: "dana-#{SecureRandom.hex(3)}@example.com", name: "Dana Ito")
    @workspace.workspace_memberships.create!(user: user, role: :member, joined_at: Time.current)
  end
end
