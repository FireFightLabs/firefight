require "test_helper"

module Integrations
  class AzureApiTest < ActiveSupport::TestCase
    SUBSCRIPTION = "11111111-2222-3333-4444-555555555555".freeze

    setup do
      @workspace = workspaces(:slack_workspace_one)
      integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "azure", name: "Azure")
      @row = integration.integration_environments.create!
      @api = AzureApi.new(tenant: "contoso.onmicrosoft.com", client_id: "client", client_secret: "s3cret", subscription: SUBSCRIPTION, token_cache: ConnectionSettings.of(@row))
    end

    test "the secret is traded for one token per audience, each cached on the row" do
      Http.expects(:request).with do |uri, request, **|
        form = URI.decode_www_form(request.body.to_s).to_h
        uri.to_s == "https://login.microsoftonline.com/contoso.onmicrosoft.com/oauth2/v2.0/token" && form["grant_type"] == "client_credentials" &&
          form["client_id"] == "client" && form["client_secret"] == "s3cret" && form["scope"] == "https://management.azure.com/.default"
      end.returns(response(200, { access_token: "arm-token", expires_in: 3599 }))
      Http.expects(:request).with do |uri, request, **|
        uri.path == "/subscriptions/#{SUBSCRIPTION}" && uri.query == "api-version=2022-12-01" && request["Authorization"] == "Bearer arm-token"
      end.returns(response(200, { subscriptionId: SUBSCRIPTION, state: "Enabled" }))

      assert_equal "Enabled", @api.subscription_details["state"]
      assert_equal "arm-token", @row.reload.credentials_hash.dig(AzureApi::TOKEN_CACHE_KEY, AzureApi::MANAGEMENT.to_s, "token")
    end

    test "a sovereign cloud signs in, reads and queries logs on its own hosts" do
      api = AzureApi.new(tenant: "contoso.onmicrosoft.us", client_id: "client", client_secret: "s3cret", subscription: SUBSCRIPTION, cloud: AzureApi::US_GOVERNMENT)
      Http.expects(:request).with do |uri, request, **|
        form = URI.decode_www_form(request.body.to_s).to_h
        uri.to_s == "https://login.microsoftonline.us/contoso.onmicrosoft.us/oauth2/v2.0/token" && form["scope"] == "https://management.usgovcloudapi.net/.default"
      end.returns(response(200, { access_token: "gov-token", expires_in: 3599 }))
      Http.expects(:request).with { |uri, *| uri.host == "management.usgovcloudapi.net" }.returns(response(200, { state: "Enabled" }))

      assert_equal "Enabled", api.subscription_details["state"]
      assert_equal "https://api.loganalytics.azure.cn/.default", AzureApi::CHINA.scope(AzureApi::LOG_ANALYTICS)
      assert_equal "https://login.partner.microsoftonline.cn", AzureApi::CHINA.login
    end

    test "a next page outside the cloud's Resource Manager is never asked with the token" do
      @api.stubs(:access_token).returns("token")
      Http.expects(:request).once.returns(response(200, { value: [ { name: "web" } ], nextLink: "https://example.com/steal?api-version=1" }))

      assert_match "outside Resource Manager", assert_raises(AzureApi::Error) { @api.list("/subscriptions/#{SUBSCRIPTION}/providers/Microsoft.Web/sites", "2025-03-01") }.message
    end

    test "a refused secret says Microsoft's reason" do
      Http.stubs(:request).returns(response(401, { error: "invalid_client", error_description: "AADSTS7000215: Invalid client secret provided.\r\nTrace ID: x" }))

      assert_equal "Microsoft refused the service principal: AADSTS7000215: Invalid client secret provided.",
                   assert_raises(AzureApi::Error) { @api.subscription_details }.message
    end

    test "a list follows nextLink, and a resource's logs are queried by its id with no doubled slash" do
      @api.stubs(:access_token).returns("token")
      Http.stubs(:request).with { |uri, *| uri.path.end_with?("/providers/Microsoft.Web/sites") && uri.query.include?("api-version") }
          .returns(response(200, { value: [ { name: "web" } ], nextLink: "https://management.azure.com/next?api-version=2025-03-01&$skiptoken=2" }))
      Http.stubs(:request).with { |uri, *| uri.path == "/next" }.returns(response(200, { value: [ { name: "api" } ] }))

      assert_equal %w[web api], @api.list("/subscriptions/#{SUBSCRIPTION}/providers/Microsoft.Web/sites", "2025-03-01").items.map { |site| site["name"] }

      id = "/subscriptions/#{SUBSCRIPTION}/resourceGroups/rg/providers/Microsoft.Web/sites/web"
      Http.expects(:request).with do |uri, request, **|
        uri.to_s == "https://api.loganalytics.io/v1/subscriptions/#{SUBSCRIPTION}/resourceGroups/rg/providers/Microsoft.Web/sites/web/query" &&
          JSON.parse(request.body) == { "query" => "AppServiceConsoleLogs", "timespan" => "PT1H" }
      end.returns(response(200, { tables: [ { name: "PrimaryResult", columns: [], rows: [] } ] }))
      @api.query_resource_logs(id, "AppServiceConsoleLogs", "PT1H")
    end

    test "Azure's refusal is raised with its own reason, and a 403 and a 429 are told apart" do
      @api.stubs(:access_token).returns("token")
      Http.stubs(:request).returns(response(403, { error: { code: "AuthorizationFailed", message: "The client does not have authorization" } }))
      assert_equal "Azure answered 403: The client does not have authorization", assert_raises(AzureApi::Forbidden) { @api.subscription_details }.message
      Http.stubs(:request).returns(response(429, { error: { message: "Too many requests" } }))
      assert_raises(Integrations::RateLimited) { @api.subscription_details }
      Http.stubs(:request).returns(stub(code: "202", body: ""))
      assert_equal({}, @api.post("/subscriptions/#{SUBSCRIPTION}/resourceGroups/rg/providers/Microsoft.Web/sites/web/restart", "2025-03-01"))
    end

    private

    def response(code, body) = stub(code: code.to_s, body: body.to_json)
  end
end
