require "test_helper"

class Mcp::Tools::SearchSimilarTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    Entitlements.stubs(:allows?).returns(true)
    FirefightAi.stubs(:embed).returns(
      Struct.new(:vectors, :model).new(Array.new(SearchEmbedding::DIMENSIONS) { 0.0 }.tap { |v| v[0] = 1.0 }, "text-embedding-3-small")
    )
    @incident.write_search_embedding!
  end

  test "a question finds the incident that reads like it, and says whether it is still open" do
    response = Mcp::Tools::SearchSimilar.perform(workspace: @workspace, args: { query: "checkout failing" })

    match = response.structured_content[:matches].first
    assert_equal "incident", match[:type]
    assert_equal @incident.identifier, match[:identifier]
    assert_equal true, match[:open]
    assert_in_delta 1.0, match[:similarity], 0.01
  end

  test "an empty question is refused rather than matched against nothing" do
    response = Mcp::Tools::SearchSimilar.perform(workspace: @workspace, args: { query: "  " })

    assert response.error?
  end

  test "the result count is capped however large a limit is asked for" do
    response = Mcp::Tools::SearchSimilar.perform(workspace: @workspace, args: { query: "anything", limit: 500 })

    assert_operator response.structured_content[:matches].size, :<=, Mcp::Tools::Base::MAX_LIMIT
  end

  test "it reads incidents, so it is authorized as one" do
    assert_equal [ Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_READ ],
                 Mcp::Tools::SearchSimilar.authorization(@workspace, {})
  end
end
