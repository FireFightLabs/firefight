module ApiTestHelper
  def api_headers(token: "ff_test_full_access_token_123456")
    {
      "Authorization" => "Bearer #{token}",
      "Content-Type" => "application/json",
      "Accept" => "application/json"
    }
  end

  def json_response
    JSON.parse(response.body)
  end

  # Service keys hold their permissions as ability grants, so minting one for a
  # test is create-then-grant. Returns [key, raw_token] like create_with_token!.
  def create_service_key(workspace:, created_by:, name: "Test Key", permissions: {}, **attrs)
    key, token = ApiKey.create_with_token!(workspace: workspace, created_by: created_by, name: name, **attrs)
    key.replace_permissions!(permissions)
    [ key, token ]
  end

  # An agent plus the token it presents. Grants hang off the agent, not the
  # token, so a rotation in a test would not change what it may do.
  def create_agent(workspace:, created_by:, name: "Test Agent", slug: "test_agent", permissions: {})
    agent = workspace.agents.create!(name: name, slug: slug)
    Ability::Grant.replace_system_grants!(principal: agent, workspace: workspace, matrix: permissions)
    _, token = ApiKey.create_with_token!(
      workspace: workspace, created_by: created_by, agent: agent, name: "#{name} token"
    )
    [ agent, token ]
  end
end
