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
end
