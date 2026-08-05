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
end
