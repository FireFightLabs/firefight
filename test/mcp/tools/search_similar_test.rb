require "test_helper"

class Mcp::Tools::SearchSimilarTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    Entitlements.stubs(:allows?).returns(true)
    FirefightAi.stubs(:embed).returns(
      Struct.new(:vectors, :model).new(Array.new(SearchEmbedding::DIMENSIONS) { 0.0 }.tap { |v| v[0] = 1.0 }, "text-embedding-3-small")
    )
    SearchEmbeddingService.new(@workspace).write!(@incident)
  end

  test "a question finds the incident that reads like it, and says whether it is still open" do
    response = Mcp::Tools::SearchSimilar.perform_with_principal(workspace: @workspace, principal: agent, args: { query: "checkout failing" })

    match = response.structured_content[:matches].first
    assert_equal "incident", match[:type]
    assert_equal @incident.identifier, match[:identifier]
    assert_equal true, match[:open]
    assert_in_delta 1.0, match[:similarity], 0.01
  end

  test "an empty question is refused rather than matched against nothing" do
    response = Mcp::Tools::SearchSimilar.perform_with_principal(workspace: @workspace, principal: agent, args: { query: "  " })

    assert response.error?
  end

  test "the result count is capped however large a limit is asked for" do
    response = Mcp::Tools::SearchSimilar.perform_with_principal(workspace: @workspace, principal: agent, args: { query: "anything", limit: 500 })

    assert_operator response.structured_content[:matches].size, :<=, Mcp::Tools::Base::MAX_LIMIT
  end

  test "a finding stays hidden from a caller who may read incidents but not investigations" do
    investigation = @workspace.investigations.create!(
      subject: @incident, trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400
    )
    SearchEmbeddingService.new(@workspace).write!(investigation.conclude!(summary: "The 14:02 deploy raised the pool size"))

    types = Mcp::Tools::SearchSimilar.perform_with_principal(
      workspace: @workspace, principal: agent, args: { query: "pool size" }
    ).structured_content[:matches].map { |match| match[:type] }

    assert_not_includes types, "finding"
  end

  test "a caller granted investigations sees the findings too" do
    investigation = @workspace.investigations.create!(
      subject: @incident, trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400
    )
    SearchEmbeddingService.new(@workspace).write!(investigation.conclude!(summary: "The 14:02 deploy raised the pool size"))
    grant_investigations!

    types = Mcp::Tools::SearchSimilar.perform_with_principal(
      workspace: @workspace, principal: agent, args: { query: "pool size" }
    ).structured_content[:matches].map { |match| match[:type] }

    assert_includes types, "finding"
  end

  # Seen in review. The tool read grant rows itself and refused a member the gateway would have let in.
  test "a member the gateway lets read investigations without a grant row sees the findings" do
    investigation = @workspace.investigations.create!(
      subject: @incident, trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400
    )
    SearchEmbeddingService.new(@workspace).write!(investigation.conclude!(summary: "The 14:02 deploy raised the pool size"))
    member = workspace_memberships(:alice_workspace_one)

    types = Mcp::Tools::SearchSimilar.perform_with_principal(
      workspace: @workspace, principal: member, args: { query: "pool size" }
    ).structured_content[:matches].map { |match| match[:type] }

    assert_includes types, "finding"
  end

  test "it reads incidents, so it is authorized as one" do
    assert_equal [ Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_READ ],
                 Mcp::Tools::SearchSimilar.authorization(@workspace, {})
  end

  private

  def agent = SystemAgent.investigator

  def grant_investigations!
    Ability::Grant.create!(
      workspace: @workspace, principal: agent,
      action: Ability::Action.system!(
        Ability::Action.system_key(Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_READ)
      )
    )
    Ability::Resolver.bust!(
      principal_type: agent.class.polymorphic_name, principal_id: agent.id, workspace_id: @workspace.id
    )
  end
end
