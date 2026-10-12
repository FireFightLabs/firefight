require "test_helper"

# Who can do what saves each dropdown through AbilityRolesController#members, from setup and from the Permissions screen.
class AbilityRoleMembersTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    @charlie = @workspace.workspace_memberships.create!(user: users(:charlie), role: :member, joined_at: Time.current)
    northflank = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Faylee")
    northflank.tools.create!(name: "list_services", read_only: true, enabled: true)
    northflank.tools.create!(name: "restart_service", read_only: false, enabled: true)
    @read = northflank.permission_packs.find_by!(pack: Ability::Role::PACK_READ)
    @changes = northflank.permission_packs.find_by!(pack: Ability::Role::PACK_CHANGES)
    sign_in(users(:alice), @workspace)
  end

  test "Nobody can read says members can no longer read it" do
    patch members_ability_role_path(@read), params: { choice: Ability::Role::NOBODY }

    assert_redirected_to gateway_permissions_path
    assert_equal "Members can no longer read Faylee (Northflank).", flash[:notice]
    assert_not @read.reload.every_member?
  end

  test "Everyone can read says members can read it" do
    @read.let_members!(Ability::Role::NOBODY)

    patch members_ability_role_path(@read), params: { choice: Ability::Role::EVERYONE }

    assert_equal "Members can read Faylee (Northflank).", flash[:notice]
    assert @read.reload.every_member?
  end

  test "choosing who can read names them" do
    patch members_ability_role_path(@read), params: { choice: Ability::Role::CHOSEN, people_ids: [ @bob.id ] }

    assert_equal "Bob Jones can read Faylee (Northflank).", flash[:notice]
    assert_equal workspace_memberships(:alice_workspace_one), @read.grants.find_by!(principal: @bob).granted_by
  end

  test "Everyone can change says members can change it" do
    patch members_ability_role_path(@changes), params: { choice: Ability::Role::EVERYONE }

    assert_equal "Members can change Faylee (Northflank).", flash[:notice]
    assert @changes.reload.every_member?
  end

  test "Nobody can change says members can no longer change it" do
    @changes.let_members!(Ability::Role::EVERYONE)

    patch members_ability_role_path(@changes), params: { choice: Ability::Role::NOBODY }

    assert_equal "Members can no longer change Faylee (Northflank).", flash[:notice]
    assert_not @changes.reload.every_member?
  end

  test "choosing who can change names them, and goes back to setup when asked from there" do
    patch members_ability_role_path(@changes), params: { choice: Ability::Role::CHOSEN, people_ids: [ @bob.id, @charlie.id ] },
                                               headers: { "Referer" => onboarding_checklist_url }

    assert_redirected_to onboarding_checklist_url
    assert_equal "Bob Jones and Charlie Brown can change Faylee (Northflank).", flash[:notice]
    assert_equal [ @bob.id, @charlie.id ].sort, @changes.grants.pluck(:principal_id).sort
  end

  test "a refusal is an alert with the model's sentence and changes nothing" do
    patch members_ability_role_path(@changes), params: { choice: Ability::Role::CHOSEN, people_ids: [] }

    assert_equal "Pick at least one person, or choose Nobody.", flash[:alert]
    assert_not @changes.grants.exists?

    patch members_ability_role_path(@changes), params: { choice: Ability::Role::CHOSEN, people_ids: [ workspace_memberships(:alice_workspace_one).id ] }

    assert_equal "Admins can always do everything, so pick members only.", flash[:alert]
    assert_not @changes.grants.exists?
  end

  test "a member cannot change who can do what" do
    sign_in(users(:bob), @workspace)

    patch members_ability_role_path(@changes), params: { choice: Ability::Role::EVERYONE }

    assert_not @changes.reload.every_member?
  end

  test "the Permissions screen shows each connection's row" do
    @changes.let_members!(Ability::Role::CHOSEN, people: [ @bob ])

    get gateway_permissions_url, headers: inertia_headers

    row = inertia_props["memberAccess"]["connections"].sole
    assert_equal "Faylee (Northflank)", row["name"]
    assert_equal [ Ability::Role::EVERYONE, @read.id ], row["read"].values_at("choice", "packId")
    assert_equal [ Ability::Role::CHOSEN, [ @bob.id ] ], row["change"].values_at("choice", "peopleIds")
  end

  private

  def sign_in(user, workspace)
    ApplicationController.any_instance.stubs(:current_user).returns(user)
    ApplicationController.any_instance.stubs(:current_workspace).returns(workspace)
    ApplicationController.any_instance.stubs(:user_signed_in?).returns(true)
  end
end
