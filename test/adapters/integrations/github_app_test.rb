require "test_helper"

module Integrations
  class GithubAppTest < ActiveSupport::TestCase
    fixtures :workspaces, :users, :workspace_memberships

    setup do
      @integration = Integration.create!(
        workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_NATIVE,
        provider: "github", name: "GitHub"
      )
      @row = @integration.integration_environments.create!(base_config: { "installation_id" => "12345" })
      @key = OpenSSL::PKey::RSA.new(2048)
      IntegrationProvider.stubs(:oauth_client).with("github").returns(
        client_id: "Iv1.abc", app_slug: "firefight", private_key: @key.to_pem
      )
    end

    test "install_url points at the app's install screen with the state threaded through" do
      url = GithubApp.install_url(state: "st-1")
      assert_equal "https://github.com/apps/firefight/installations/new?state=st-1", url
    end

    test "install_url is nil when no app slug is configured" do
      IntegrationProvider.stubs(:oauth_client).with("github").returns({})
      assert_nil GithubApp.install_url(state: "st-1")
    end

    test "the app JWT is RS256 signed with the client id as issuer" do
      token = GithubApp.send(:app_jwt)
      payload, header = JWT.decode(token, @key.public_key, true, algorithm: "RS256")

      assert_equal "RS256", header["alg"]
      assert_equal "Iv1.abc", payload["iss"]
      assert_operator payload["exp"], :>, Time.current.to_i
    end

    test "a cached installation token is reused until close to expiry" do
      @row.update!(credentials: {
        GithubApp::TOKEN_CACHE_KEY => { "token" => "ghs_cached", "expires_at" => 30.minutes.from_now.iso8601 }
      }.to_json)
      GithubApp.expects(:mint_token).never

      assert_equal "ghs_cached", GithubApp.installation_token(@row)
    end

    test "a stale token is re-minted and the cache persisted" do
      @row.update!(credentials: {
        GithubApp::TOKEN_CACHE_KEY => { "token" => "ghs_old", "expires_at" => 1.minute.from_now.iso8601 }
      }.to_json)
      response = stub(code: "201", body: { token: "ghs_new", expires_at: 1.hour.from_now.iso8601 }.to_json)
      Net::HTTP.stubs(:start).returns(response)

      assert_equal "ghs_new", GithubApp.installation_token(@row)
      assert_equal "ghs_new", @row.reload.credentials_hash[GithubApp::TOKEN_CACHE_KEY]["token"]
    end

    test "a connection without an installation id explains how to fix it" do
      @row.update!(base_config: {})

      error = assert_raises(GithubApp::Error) { GithubApp.installation_token(@row) }
      assert_match(/Reconnect GitHub/, error.message)
    end

    test "API errors surface GitHub's message" do
      response = stub(code: "404", body: { message: "Not Found" }.to_json)
      Net::HTTP.stubs(:start).returns(response)

      error = assert_raises(GithubApp::Error) { GithubApp.get("/repos/acme/checkout/pulls/1", token: "t") }
      assert_match(/Not Found/, error.message)
    end
  end
end
