require "test_helper"

# How often a reply and an investigation read the workspace's connection tools whole. Every path in one reads the
# catalogue its run holds, and a reply after the first reads them from the cache.
class Chat::ToolCatalogueReadsTest < ActiveSupport::TestCase
  WHOLE_READS = /AS t0_r0\b.*FROM "integration_tools"|SELECT "integration_tools"\.\* FROM "integration_tools"/

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)
    fake = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "fake", name: "Fake", slug: "fake")
    fake.integration_environments.create!(credentials: { token: "x" }.to_json)
    @echo = fake.tools.create!(name: "echo_text", description: "Echoes", params_schema: { "type" => "object" }, enabled: true, read_only: true)
    @write = fake.tools.create!(name: "write_text", description: "Writes", params_schema: { "type" => "object" }, enabled: true, read_only: false)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
  end

  test "a reply that asks specialists and reads deploys several times reads the tools whole at most once, and none once cached" do
    assert_operator whole_reads { reply }, :<=, 1
    assert_equal 0, whole_reads { reply }
  end

  test "an investigation run reads the tools whole at most once, and none once cached" do
    investigation = Investigation.create!(workspace: @workspace, subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_DASHBOARD,
                                          max_spend_cents: 100, max_turns: 5)

    assert_operator whole_reads { investigate(Investigation.find(investigation.id)) }, :<=, 1
    assert_equal 0, whole_reads { investigate(Investigation.find(investigation.id)) }
  end

  test "a grant revoked between replies is seen on the next" do
    member = workspace_memberships(:bob_workspace_one)
    grant = Ability::Grant.grant!(workspace: @workspace, principal: member, target: { action: @write.ability_action })
    assert_equal Chat::Tools::STATE_READY, entry(turn(member), @write).state

    grant.destroy!

    assert_equal Chat::Tools::STATE_NOT_GRANTED, entry(turn(member), @write).state
  end

  test "a tool switched off between replies is gone from the next" do
    assert entry(turn, @echo)

    @echo.update!(enabled: false)

    assert_nil entry(turn, @echo)
  end

  private

  def turn(member = @member) = Conversation::Turn.new(Conversation.find(@conversation.id), asker: WorkspaceMembership.find(member.id))

  def entry(turn, tool) = Chat::Tools.catalog(turn).find { |each| each.name.to_s == tool.model_facing_name }

  # What one reply reaches for, on a workspace read afresh as a new request or job reads it.
  def reply
    turn = self.turn
    workspace = turn.workspace
    Chat::Tools.catalog(turn)
    live = Chat::Specialists::Live.new(turn)
    live.views
    live.tools(Chat::Helpers::Agent.new(Chat::Helper.new, parent: turn), Chat::Specialists::DOMAINS.first)
    3.times { Chat::Tools::DeploySpan.callable(turn) }
    Chat::Tools.connection_entries(turn)
    Chat::Tools.capability_entries(turn)
    Chat::Specialists.backing(workspace, [ @write.model_facing_name ])
    Chat::Tools::Target.connection_tool(workspace, @echo.model_facing_name)
    Conversation::Mitigations.undo_tools(workspace)
    Chat::Tools::SkillTools.provider_handles(workspace, "fake")
    Integrations::Capabilities.offered(workspace)
  end

  def investigate(investigation)
    3.times { Chat::Tools.catalog(investigation) }
    Integrations::Capabilities.offered(investigation.workspace)
    Integrations::Capabilities.outside_checkers(investigation.workspace)
  end

  def whole_reads(&) = queries_sent(cached: true, transactions: true, &).grep(WHOLE_READS).size
end
