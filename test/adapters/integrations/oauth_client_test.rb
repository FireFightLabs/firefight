require "test_helper"

module Integrations
  class OauthClientTest < ActiveSupport::TestCase
    STACK_SERVER = "https://mcp.grafana.com/mcp/mystack.grafana.net".freeze
    SCOPES = [ "grafana:read", "grafana:query", "grafana:write" ].freeze

    # The shapes Grafana Cloud's hosted server answers for one stack: the resource metadata names the stack's own
    # authorization server, whose authorization endpoint carries the stack in its query.
    def stub_stack_metadata
      OauthClient.stubs(:get_json).returns(nil)
      OauthClient.stubs(:get_json).with("https://mcp.grafana.com/.well-known/oauth-protected-resource/mcp/mystack.grafana.net", provider_key: nil).returns(
        "resource" => "https://mcp.grafana.com/mcp", "authorization_servers" => [ STACK_SERVER ], "scopes_supported" => SCOPES
      )
      OauthClient.stubs(:get_json).with("https://mcp.grafana.com/.well-known/oauth-authorization-server/mcp/mystack.grafana.net", provider_key: nil).returns(
        "issuer" => STACK_SERVER,
        "authorization_endpoint" => "https://mcp.grafana.com/mcp/oauth/authorize?grafana_url=https%3A%2F%2Fmystack.grafana.net",
        "token_endpoint" => "https://mcp.grafana.com/mcp/oauth/token", "registration_endpoint" => "https://mcp.grafana.com/mcp/oauth/register"
      )
    end

    def token_response(code, body)
      PublicAddress.stubs(:check!).returns(PublicAddress::Checked.new(ip: IPAddr.new("93.184.216.34"), private: false))
      Http.stubs(:request).returns(stub(code: code.to_s, body: body.to_json))
    end

    test "a stack's own authorization server is found through the stack's resource metadata, and only the scopes asked for are asked" do
      stub_stack_metadata

      metadata = OauthClient.discover(STACK_SERVER, {}, [ "grafana:read" ])

      assert_equal "https://mcp.grafana.com/mcp/oauth/token", metadata[:token_endpoint]
      assert_equal "https://mcp.grafana.com/mcp/oauth/register", metadata[:registration_endpoint]
      assert_equal "grafana:read", metadata[:scope]
      assert_equal SCOPES.join(" "), OauthClient.discover(STACK_SERVER)[:scope], "without a narrower list every scope the server lists is asked"
    end

    test "a scope the server does not list is refused, and a server that lists none is asked for none" do
      stub_stack_metadata

      error = assert_raises(OauthClient::Error) { OauthClient.discover(STACK_SERVER, {}, [ "grafana:admin" ]) }
      assert_equal "the server no longer offers grafana:admin", error.message

      OauthClient.stubs(:get_json).returns(nil)
      OauthClient.stubs(:get_json).with("https://mcp.example/.well-known/oauth-protected-resource/mcp", provider_key: nil).returns("authorization_servers" => [ "https://auth.example" ])
      OauthClient.stubs(:get_json).with("https://auth.example/.well-known/oauth-authorization-server", provider_key: nil).returns(
        "authorization_endpoint" => "https://auth.example/authorize", "token_endpoint" => "https://auth.example/token"
      )
      assert_nil OauthClient.discover("https://mcp.example/mcp", {}, [ "read" ])[:scope]
    end

    test "the sign-in keeps the query the authorization endpoint carries, so it opens on the stack" do
      stub_stack_metadata
      OauthClient.stubs(:register).returns("dcr-client")

      flow = OauthClient.begin_flow(server_url: STACK_SERVER, redirect_uri: "https://ff.example/cb", scopes: [ "grafana:read" ])

      uri = URI.parse(flow[:authorize_url])
      query = Rack::Utils.parse_query(uri.query)
      assert_equal "https://mcp.grafana.com/mcp/oauth/authorize", "#{uri.scheme}://#{uri.host}#{uri.path}"
      assert_equal "https://mystack.grafana.net", query["grafana_url"]
      assert_equal "dcr-client", query["client_id"]
      assert_equal "grafana:read", query["scope"]
      assert_equal "S256", query["code_challenge_method"]
      assert_equal STACK_SERVER, query["resource"]
      assert_equal "dcr-client", flow[:client_id]
    end

    test "a refresh token the server no longer takes ends the sign-in, and any other refusal stays an error" do
      credentials = { "access_token" => "old", "refresh_token" => "rt", "token_endpoint" => "https://auth.example/token", "client_id" => "cid" }

      token_response(400, { error: "invalid_grant", error_description: "refresh token expired" })
      ended = assert_raises(OauthClient::SignInEnded) { OauthClient.refresh(credentials) }
      assert_equal "refresh token expired", ended.message

      token_response(500, { error: "server_error" })
      error = assert_raises(OauthClient::Error) { OauthClient.refresh(credentials) }
      assert_not_kind_of OauthClient::SignInEnded, error
    end

    test "discovery never reaches a private address, whether the workspace typed it or the server it named answered it" do
      PublicAddress.stubs(:resolve).with("10.0.0.5").returns(IPAddr.new("10.0.0.5"))
      Http.expects(:request).never

      error = assert_raises(OauthClient::Error) { OauthClient.discover("https://10.0.0.5/mcp") }
      assert_equal "10.0.0.5 is on a private network, which Firefight does not connect to.", error.message

      PublicAddress.stubs(:resolve).with("mcp.example").returns(IPAddr.new("93.184.216.34"))
      PublicAddress.stubs(:resolve).with("metadata.internal").returns(IPAddr.new("169.254.169.254"))
      metadata = { registration_endpoint: "http://metadata.internal/latest/meta-data" }
      assert_raises(OauthClient::Error) { OauthClient.send(:register, metadata, "https://ff.example/cb") }
    end

    test "a token request goes to the address that was checked" do
      PublicAddress.stubs(:resolve).with("auth.example").returns(IPAddr.new("93.184.216.34"))
      Http.expects(:request).with { |_uri, _request, ipaddr:, **| ipaddr == "93.184.216.34" }
          .returns(stub(code: "200", body: { access_token: "new" }.to_json))

      OauthClient.refresh({ "refresh_token" => "rt", "token_endpoint" => "https://auth.example/token", "client_id" => "cid" })
    end

    test "a refresh keeps the new tokens and the expiry the server gave" do
      credentials = { "access_token" => "old", "refresh_token" => "rt", "token_endpoint" => "https://auth.example/token", "client_id" => "cid" }
      token_response(200, { access_token: "new", refresh_token: "rt-2", expires_in: 3600 })

      rotated = OauthClient.refresh(credentials)

      assert_equal [ "new", "rt-2", "cid" ], rotated.values_at("access_token", "refresh_token", "client_id")
      assert_in_delta 1.hour.from_now, Time.zone.parse(rotated["expires_at"]), 5.seconds
    end
  end
end
