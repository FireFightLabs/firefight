require "test_helper"

# Creating an agent is creating a principal: it gets a name of its own, a token
# it presents, and nothing else until someone grants it something.
class AgentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    sign_in(users(:alice), @workspace)
  end

  test "creating an agent mints its first token and reveals it once" do
    assert_difference -> { @workspace.agents.count }, 1 do
      post gateway_agents_url, params: { name: "Support agent", slug: "support_agent" }
    end

    agent = @workspace.agents.find_by!(slug: "support_agent")
    assert_equal 1, agent.api_keys.count
    assert_match(/\Aff_/, revealed_token)
    assert_match(/Support agent/, flash[:notice])
  end

  test "a new agent can authenticate and still do nothing" do
    post gateway_agents_url, params: { name: "Support agent", slug: "support_agent" }
    agent = @workspace.agents.find_by!(slug: "support_agent")

    assert agent.credentialed?
    assert_equal 0, agent.ability_grants.count
    assert_not agent.mcp_readable?(Ability::Action::RESOURCE_INCIDENTS)
  end

  test "a slug that is not machine-readable is refused" do
    assert_no_difference -> { @workspace.agents.count } do
      post gateway_agents_url, params: { name: "Support agent", slug: "Support Agent" }
    end
  end

  test "two agents cannot share a slug in one workspace" do
    post gateway_agents_url, params: { name: "First", slug: "duplicate" }

    assert_no_difference -> { @workspace.agents.count } do
      post gateway_agents_url, params: { name: "Second", slug: "duplicate" }
    end
  end

  # Rotation overlaps rather than swaps, so an agent mid-incident keeps running
  # on the old token until someone revokes it.
  test "rotating leaves the old token working alongside the new one" do
    agent, old_token = create_agent(
      workspace: @workspace, created_by: workspace_memberships(:alice_workspace_one), slug: "rotator"
    )

    assert_difference -> { agent.api_keys.count }, 1 do
      post rotate_gateway_agent_url(agent)
    end

    assert_match(/\Aff_/, revealed_token)
    assert_not_equal revealed_token, old_token
    assert_equal agent, ApiKey.authenticate(old_token).principal
  end

  test "rotating keeps the abilities the agent already holds" do
    agent, = create_agent(
      workspace: @workspace, created_by: workspace_memberships(:alice_workspace_one),
      slug: "rotator", permissions: { Ability::Action::RESOURCE_INCIDENTS => %w[read create] }
    )

    post rotate_gateway_agent_url(agent)

    assert_equal 2, agent.reload.ability_grants.count
    assert agent.mcp_readable?(Ability::Action::RESOURCE_INCIDENTS)
  end

  # A disabled agent still holds its slug and its grants, so it stays on the
  # list with a way back on.
  test "a disabled agent stays on the roster" do
    agent, = create_agent(
      workspace: @workspace, created_by: workspace_memberships(:alice_workspace_one), slug: "pausable"
    )

    patch gateway_agent_url(agent), params: { enabled: false }
    assert_not agent.reload.enabled?

    assert_includes listed_agent_ids(gateway_agents_url), agent.id

    patch gateway_agent_url(agent), params: { enabled: true }
    assert agent.reload.enabled?
  end

  test "revoking one token of two leaves the agent working" do
    agent, old_token = create_agent(
      workspace: @workspace, created_by: workspace_memberships(:alice_workspace_one), slug: "two_tokens"
    )
    post rotate_gateway_agent_url(agent)
    revoked = ApiKey.authenticate(old_token)

    delete gateway_agent_token_url(agent, revoked)

    assert_nil ApiKey.authenticate(old_token)
    assert agent.reload.credentialed?
    assert_match(/keeps working/, flash[:notice])
  end

  test "revoking the last token says the agent can no longer act" do
    agent, token = create_agent(
      workspace: @workspace, created_by: workspace_memberships(:alice_workspace_one), slug: "one_token"
    )

    delete gateway_agent_token_url(agent, ApiKey.authenticate(token))

    assert_not agent.reload.credentialed?
    assert_match(/cannot act/, flash[:notice])
  end

  test "another agent's token cannot be revoked through this one" do
    membership = workspace_memberships(:alice_workspace_one)
    mine, = create_agent(workspace: @workspace, created_by: membership, slug: "mine")
    theirs, their_token = create_agent(workspace: @workspace, created_by: membership, slug: "theirs")

    delete gateway_agent_token_url(mine, theirs.api_keys.first)

    assert_response :not_found
    assert_not_nil ApiKey.authenticate(their_token)
  end

  # Agent credentials belong to the agent, not to the workspace's developer
  # keys, so they are managed in one place rather than two.
  test "an agent's token is not listed among the developer api keys" do
    agent, = create_agent(
      workspace: @workspace, created_by: workspace_memberships(:alice_workspace_one), slug: "hidden_key"
    )

    assert_not_includes listed_api_key_ids(developer_api_keys_url), agent.api_keys.first.id
  end

  test "deleting an agent takes its tokens with it" do
    agent, token = create_agent(
      workspace: @workspace, created_by: workspace_memberships(:alice_workspace_one), slug: "doomed"
    )

    assert_difference -> { ApiKey.count }, -1 do
      delete gateway_agent_url(agent)
    end

    assert_nil ApiKey.authenticate(token)
  end

  test "another workspace's agent is not reachable" do
    agent, = create_agent(
      workspace: workspaces(:slack_workspace_two),
      created_by: workspace_memberships(:alice_workspace_two), slug: "elsewhere"
    )

    delete gateway_agent_url(agent)

    assert_response :not_found
    assert agent.reload.persisted?
  end

  test "a member without permissions cannot create an agent" do
    sign_in(users(:bob), @workspace)

    assert_no_difference -> { @workspace.agents.count } do
      post gateway_agents_url, params: { name: "Sneaky", slug: "sneaky" }
    end
  end

  # Agents are principals, so they show up wherever grants are handed out.
  test "an agent appears on the permissions screen as a grantable principal" do
    agent, = create_agent(
      workspace: @workspace, created_by: workspace_memberships(:alice_workspace_one), slug: "grantable"
    )

    assert_includes Ability::Principal.all(@workspace), agent
    assert_equal agent, Ability::Principal.find!(@workspace, Ability::Principal::KIND_AGENT, agent.id)
  end

  private

  # The one-time token rides Inertia's own flash bucket, not a top-level key.
  def revealed_token
    flash[:inertia]&.dig("api_key_token")
  end

  def listed_agent_ids(url)
    inertia_props(url)["agents"].map { |agent| agent["id"] }
  end

  def listed_api_key_ids(url)
    inertia_props(url)["apiKeys"].map { |key| key["id"] }
  end

  # Asking Inertia for the page as JSON, which is the props the screen renders.
  def inertia_props(url)
    get url, headers: { "X-Inertia" => "true", "X-Inertia-Version" => InertiaRails.configuration.version.to_s }
    JSON.parse(response.body).fetch("props")
  end
end
