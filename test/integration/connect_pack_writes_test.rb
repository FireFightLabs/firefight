require "test_helper"

# Connecting a provider writes each of its tools, the action each tool mints and that action's place in the connection's
# permission packs. The packs are filed once every tool is saved rather than tool by tool.
class ConnectPackWritesTest < ActionDispatch::IntegrationTest
  # Filing tool by tool took 924 statements to connect AWS's 25 tools, about 37 a tool. Filed together it is 389. Each
  # tool still saves itself and mints its action with its own checks, and the packs are a few statements in all.
  MOST_QUERIES_A_TOOL = 16

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:bob_workspace_one)
    sign_in(users(:alice), @workspace)
    Integrations::AwsApi.any_instance.stubs(:identity).returns(account: "123456789012", arn: "arn:aws:iam::123456789012:user/firefight")
    Integrations::AwsApi.any_instance.stubs(:all).returns([ [], false ])
    Integrations::MapSweepJob.stubs(:perform_later)
  end

  test "connecting AWS's tools files their packs together, in well under half the queries filing each tool took" do
    queries = queries_sent(cached: true, transactions: true) { connect_aws }.size

    tools = aws.tools.enabled.count
    assert_operator tools, :>=, 25
    assert_operator queries, :<=, MOST_QUERIES_A_TOOL * tools
  end

  test "the packs and actions connecting writes are the ones filing each action on its own gives" do
    connect_aws
    connected = snapshot(aws)
    actions = Ability::Action.where(source: aws.tools).to_a
    Ability::RoleAction.where(action: actions).delete_all
    actions.each { |action| Ability::Role.file!(action, aws) }

    assert_equal connected, snapshot(aws)
    reads, changes = actions.partition(&:read?).map { |group| group.map(&:key).sort }
    assert_equal({ Ability::Role::PACK_READ => reads, Ability::Role::PACK_CHANGES => changes, Ability::Role::PACK_EVERYTHING => (reads + changes).sort,
                   Ability::Role::PACK_CHANGES_EVERYWHERE => changes },
                 connected["packs"].to_h { |pack| [ pack["pack"], pack["actions"].map(&:first) ] })
    assert_equal [ [ SystemAgent.name, SystemAgent.investigator.id, Ability::Role::PACK_READ, nil ] ], connected["grants"]
  end

  test "switching every tool on files them together and clears the caches of whoever holds the packs they join" do
    Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "aws", name: "AWS")
    integration.integration_environments.create!
    restart = integration.tools.create!(name: "restart_service", read_only: false, enabled: false)
    everywhere = @workspace.ability_roles.find_by!(pack: Ability::Role::PACK_CHANGES_EVERYWHERE)
    @workspace.ability_grants.create!(principal: @member, role: everywhere, scope: {})
    assert_not Ability::Resolver.resolve(@member, @workspace).by_key.key?(restart.action_key)

    patch set_all_tools_integration_path(integration), params: { enabled: true }

    assert_equal "Every tool on AWS is on.", flash[:notice]
    assert Ability::Resolver.resolve(@member, @workspace).by_key.key?(restart.action_key)
    assert_equal [ restart.reload.ability_action ], everywhere.actions.to_a
  end

  test "a tool's action minted before discovery fails is still filed, as filing it straight away was" do
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "aws", name: "AWS")
    tool = integration.tools.create!(name: "restart_service", read_only: false, enabled: false)

    assert_raises(ActiveRecord::RecordInvalid) do
      Ability::Role.filing_together(integration) do
        tool.update!(enabled: true)
        integration.tools.create!(name: "Not A Name")
      end
    end

    assert_equal [ tool.ability_action ], integration.permission_packs.find_by!(pack: Ability::Role::PACK_CHANGES).actions.to_a
  end

  private

  def aws = @workspace.integrations.find_by!(provider: "aws")

  def connect_aws
    post integrations_path, params: { provider: "aws", name: "AWS",
                                      credentials: { "access_key_id" => "AKIAEXAMPLE", "secret_access_key" => "secret" },
                                      fields: { "regions" => [ "eu-west-1", "us-east-1" ] } }
    assert_equal "AWS is connected.", flash[:notice]
  end

  # Everything connecting writes about permissions, in a form two connections can be compared by.
  def snapshot(integration)
    actions = Ability::Action.where(source: integration.tools).order(:key)
    packs = @workspace.ability_roles.where(integration_id: [ integration.id, nil ]).where.not(pack: nil).order(:pack)
    {
      "actions" => actions.map { |action| action.slice(:key, :kind, :risk_level, :reversible, :params_schema).merge("tool" => action.source.name) },
      "packs" => packs.map do |pack|
        rows = pack.role_actions.includes(:action).map { |row| [ row.action.key, row.default_scope ] }
        pack.slice(:pack, :name, :slug, :description).merge("actions" => rows.select { |key, _| key.start_with?("#{integration.slug}.") }.sort)
      end,
      "grants" => @workspace.ability_grants.where(role: packs).or(@workspace.ability_grants.where(action: actions))
                            .map { |grant| [ grant.principal_type, grant.principal_id, grant.role&.pack, grant.action&.key ] }.sort_by(&:to_s)
    }
  end
end
