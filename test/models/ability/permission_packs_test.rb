require "test_helper"

class Ability::PermissionPacksTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:bob_workspace_one)
    @production = catalog_entries(:production_env)
    @development = catalog_entries(:development_env)
    @northflank = connect("Faylee", "northflank")
    @list = @northflank.tools.create!(name: "list_services", read_only: true, enabled: true)
    @restart = @northflank.tools.create!(name: "restart_service", read_only: false, enabled: true)
  end

  test "connecting makes the connection's read, changes and everything packs, named after it, and Changes everywhere" do
    assert_equal({ "read" => "Faylee (Northflank): read", "changes" => "Faylee (Northflank): changes", "everything" => "Faylee (Northflank): everything" },
                 @northflank.permission_packs.to_h { |pack| [ pack.pack, pack.name ] })
    assert_equal [ @list.ability_action ], pack(Ability::Role::PACK_READ).actions.to_a
    assert_equal [ @restart.ability_action ], pack(Ability::Role::PACK_CHANGES).actions.to_a
    assert_equal [ @list.ability_action, @restart.ability_action ].sort_by(&:key), pack(Ability::Role::PACK_EVERYTHING).actions.sort_by(&:key)
    assert_equal [ @restart.ability_action ], everywhere.actions.to_a
    assert_equal "Every tool on Faylee (Northflank) that only reads.", pack(Ability::Role::PACK_READ).description
  end

  test "a tool switched on later joins the packs its read-only flag puts it in, and moves when the flag changes" do
    logs = @northflank.tools.create!(name: "search_logs", read_only: true, enabled: true)
    assert_includes pack(Ability::Role::PACK_READ).actions, logs.ability_action
    assert_not_includes everywhere.actions, logs.ability_action

    logs.update!(read_only: false)

    assert_not_includes pack(Ability::Role::PACK_READ).actions.reload, logs.ability_action
    assert_includes pack(Ability::Role::PACK_CHANGES).actions, logs.ability_action
    assert_includes pack(Ability::Role::PACK_EVERYTHING).actions, logs.ability_action
    assert_includes everywhere.actions, logs.ability_action
  end

  test "Changes everywhere covers a connection made after it, and a member holding it reaches the new connection's changes" do
    @workspace.ability_grants.create!(principal: @member, role: everywhere, scope: {})
    github = connect("GitHub", "github")
    merge = github.tools.create!(name: "merge_pull_request", read_only: false, enabled: true)

    assert_includes everywhere.actions, merge.ability_action
    assert authorize(@member, merge.action_key)
  end

  test "renaming a connection renames its packs, and disconnecting it takes them and their grants away" do
    grant = @workspace.ability_grants.create!(principal: @member, role: pack(Ability::Role::PACK_CHANGES), scope: {})

    @northflank.update!(name: "faylee")
    assert_equal "faylee (Northflank): changes", pack(Ability::Role::PACK_CHANGES).name

    @northflank.update!(deleted_at: Time.current)
    assert_empty @northflank.permission_packs.reload
    assert_not Ability::Grant.exists?(grant.id)
    assert_not_includes everywhere.actions.reload, @restart.ability_action
  end

  test "a pack is never edited or deleted by hand, and says why" do
    read = pack(Ability::Role::PACK_READ)

    error = assert_raises(ActiveRecord::RecordInvalid) { read.sync_actions!([]) }
    assert_match "Faylee (Northflank): read is kept in step with Faylee (Northflank)'s tools, so it cannot be changed by hand.", error.message
    assert_raises(ActiveRecord::RecordInvalid) { read.update!(name: "Mine now") }
    error = assert_raises(ActiveRecord::RecordInvalid) { read.destroy_by_hand! }
    assert_match "goes when Faylee (Northflank) is disconnected", error.message
    assert_not read.destroy
    error = assert_raises(ActiveRecord::RecordInvalid) { everywhere.destroy_by_hand! }
    assert_match "Changes everywhere is built in, so it cannot be deleted.", error.message
    assert_equal [ @list.ability_action ], read.reload.actions.to_a
  end

  test "a hand-made set already called what a pack would be keeps its slug, and the pack takes the next free one" do
    @workspace.ability_roles.create!(name: "GitHub read")

    github = connect("GitHub", "github")

    assert_equal "github_read_2", github.permission_packs.find_by!(pack: Ability::Role::PACK_READ).slug
  end

  test "a member reads every connected tool without a grant and is refused a change, told which pack to ask for" do
    assert authorize(@member, @list.action_key)
    assert_raises(AbilityGateway::Denied) { authorize(@member, @restart.action_key) }

    turn = Conversation::Turn.new(Conversation.start_personal!(workspace: @workspace, member: @member), asker: @member)
    assert_equal "Not allowed: Bob Jones cannot use faylee.restart_service in this workspace. Tell them they do not have permission for it and " \
                 "that it needs the Faylee (Northflank): changes pack. The workspace admin is Alice Smith. A card in the chat lets them ask the " \
                 "admins for it. #{Chat::StaleRefusals::AS_READ}", turn.refusal(@restart.action_key)
    assert_equal "Not allowed: Bob Jones cannot use faylee.list_services in this workspace. Tell them, and that a workspace admin can grant it. " \
                 "#{Chat::StaleRefusals::AS_READ}", turn.refusal(@list.action_key)
  end

  test "a changes pack scoped to an environment lets a member change things only there" do
    Ability::Grant.grant!(workspace: @workspace, principal: @member, target: { role: pack(Ability::Role::PACK_CHANGES) }, environment_ids: [ @production.id ])

    assert authorize(@member, @restart.action_key, scope: { "environment" => @production.id })
    assert_raises(AbilityGateway::Denied) { authorize(@member, @restart.action_key, scope: { "environment" => @development.id }) }
  end

  test "a read pack granted for one environment narrows a member's reads to it" do
    Ability::Grant.grant!(workspace: @workspace, principal: @member, target: { role: pack(Ability::Role::PACK_READ) }, environment_ids: [ @production.id ])

    assert authorize(@member, @list.action_key, scope: { "environment" => @production.id })
    assert_raises(AbilityGateway::Denied) { authorize(@member, @list.action_key, scope: { "environment" => @development.id }) }
  end

  test "no access on a connection's reads takes them away at once, a tool added later included, and revoking it gives them back" do
    read = pack(Ability::Role::PACK_READ)
    grant = Ability::Grant.withhold!(workspace: @workspace, principal: @member, role: read)

    assert_raises(AbilityGateway::Denied) { authorize(@member, @list.action_key) }
    logs = @northflank.tools.create!(name: "search_logs", read_only: true, enabled: true)
    assert_raises(AbilityGateway::Denied) { authorize(@member, logs.action_key) }
    assert_equal [ [ read.name, WorkspaceMembership::DEFAULT_NO_ACCESS ] ],
                 @member.default_access.select(&:role).map { |access| [ access.role.name, access.state ] }

    grant.destroy!
    assert authorize(@member, logs.action_key)
  end

  test "no access is refused on a pack that is not a connection's reads" do
    error = assert_raises(ActiveRecord::RecordInvalid) do
      Ability::Grant.withhold!(workspace: @workspace, principal: @member, role: pack(Ability::Role::PACK_CHANGES))
    end
    assert_match Ability::Grant::NO_ACCESS_ONLY_FOR_DEFAULTS, error.message
  end

  test "a service key or an agent reaches no tool until a pack or a grant is given to it" do
    key = api_keys(:full_access_key)
    assert_raises(AbilityGateway::Denied) { authorize(key, @list.action_key) }

    @workspace.ability_grants.create!(principal: key, role: pack(Ability::Role::PACK_READ), scope: {})

    assert authorize(key, @list.action_key)
    assert_raises(AbilityGateway::Denied) { authorize(key, @restart.action_key) }
  end

  test "the investigator is given each connection's reads when it is connected, and an admin revoking them keeps them revoked" do
    investigator = SystemAgent.investigator
    assert authorize(investigator, @list.action_key)
    assert_raises(AbilityGateway::Denied) { authorize(investigator, @restart.action_key) }

    @workspace.ability_grants.find_by!(principal: investigator, role: pack(Ability::Role::PACK_READ)).destroy!
    logs = @northflank.tools.create!(name: "search_logs", read_only: true, enabled: true)
    @northflank.update!(name: "Faylee two")

    assert_raises(AbilityGateway::Denied) { authorize(investigator, logs.action_key) }
    assert_not @workspace.ability_grants.exists?(principal: investigator, role: pack(Ability::Role::PACK_READ))
  end

  private

  def connect(name, provider)
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: provider, name: name)
    integration.integration_environments.create!(catalog_entry_id: @production.id)
    integration.integration_environments.create!(catalog_entry_id: @development.id)
    integration
  end

  def pack(kind) = @northflank.permission_packs.find_by!(pack: kind)

  def everywhere = @workspace.ability_roles.find_by!(pack: Ability::Role::PACK_CHANGES_EVERYWHERE)

  def authorize(principal, action_key, scope: { "environment" => @production.id })
    AbilityGateway.authorize!(principal: principal, action_key: action_key, workspace: @workspace, scope: scope) { true }
  end
end
