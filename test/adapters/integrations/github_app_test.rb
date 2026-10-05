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

    test "a GraphQL answer with errors is refused with GitHub's words, since it still arrives as a success" do
      response = stub(code: "200", body: { data: nil, errors: [ { message: "Could not resolve to a Commit." }, { message: "Path not found" } ] }.to_json)
      Net::HTTP.stubs(:start).returns(response)

      error = assert_raises(GithubApp::Error) { GithubApp.graphql("query { x }", {}, token: "t") }
      assert_equal "GitHub: Could not resolve to a Commit, Path not found", error.message
    end

    test "API errors surface GitHub's message" do
      response = stub(code: "404", body: { message: "Not Found" }.to_json)
      Net::HTTP.stubs(:start).returns(response)

      error = assert_raises(GithubApp::Error) { GithubApp.get("/repos/acme/checkout/pulls/1", token: "t") }
      assert_match(/Not Found/, error.message)
    end
    test "a pull request is one commit on a new branch off base, each file a blob, a deleted one dropped from the tree" do
      GithubApp.stubs(:get).with("/repos/acme/api/git/commits/base-sha", token: "t").returns("tree" => { "sha" => "base-tree" })
      GithubApp.expects(:post).with("/repos/acme/api/git/blobs", { content: "cG9vbA==", encoding: "base64" }, token: "t").returns("sha" => "blob-1")
      GithubApp.expects(:post).with("/repos/acme/api/git/trees", { base_tree: "base-tree", tree: [
        { path: "config/database.yml", mode: "100644", type: "blob", sha: "blob-1" }, { path: "old.rb", mode: "100644", type: "blob", sha: nil }
      ] }, token: "t").returns("sha" => "tree-1")
      GithubApp.expects(:post).with("/repos/acme/api/git/commits", { message: "Restore the pool", tree: "tree-1", parents: [ "base-sha" ] }, token: "t")
               .returns("sha" => "commit-1")
      GithubApp.expects(:post).with("/repos/acme/api/git/refs", { ref: "refs/heads/halon/fix-1", sha: "commit-1" }, token: "t").returns({})
      GithubApp.expects(:post).with("/repos/acme/api/pulls", { title: "Restore the pool", head: "halon/fix-1", base: "main", body: "Why", draft: false }, token: "t")
               .returns("html_url" => "https://github.com/acme/api/pull/7")

      opened = GithubApp.open_pull_request("acme/api", base: "main", base_sha: "base-sha", branch: "halon/fix-1", title: "Restore the pool", body: "Why", message: "Restore the pool",
                                                       files: { "config/database.yml" => { mode: "100644", content: "cG9vbA==" }, "old.rb" => nil }, token: "t")

      assert_equal "https://github.com/acme/api/pull/7", opened["html_url"]
    end

    test "a job's log is fetched from the signed address GitHub redirects to, without the token, and only on a public host" do
      redirect = Net::HTTPFound.new("1.1", "302", "Found")
      redirect["location"] = "https://pipelines.actions.githubusercontent.com/logs/9?sig=1"
      log = Net::HTTPOK.new("1.1", "200", "OK")
      log.instance_variable_set(:@body, "step one\nfailed here\n")
      log.instance_variable_set(:@read, true)
      Addrinfo.stubs(:getaddrinfo).with("pipelines.actions.githubusercontent.com", nil, nil, :STREAM).returns([ stub(ip_address: "140.82.112.21") ])
      sent = []
      Http.stubs(:request).with { |uri, request, **options| sent << [ uri.host, request["Authorization"], options[:ipaddr] ] }.returns(redirect).then.returns(log)

      assert_equal "step one\nfailed here\n", GithubApp.download("/repos/acme/web/actions/jobs/9/logs", token: "ghs_token")
      assert_equal [ [ "api.github.com", "Bearer ghs_token", nil ], [ "pipelines.actions.githubusercontent.com", nil, "140.82.112.21" ] ], sent

      Addrinfo.stubs(:getaddrinfo).with("pipelines.actions.githubusercontent.com", nil, nil, :STREAM).returns([ stub(ip_address: "10.0.0.8") ])
      Http.stubs(:request).returns(redirect)
      assert_match "private network", assert_raises(GithubApp::Error) { GithubApp.download("/repos/acme/web/actions/jobs/9/logs", token: "ghs_token") }.message
    end
  end
end
