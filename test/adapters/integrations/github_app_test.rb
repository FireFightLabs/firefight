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

    test "a commit pushed to an existing branch moves it without forcing, so a branch that moved since is refused" do
      GithubApp.stubs(:get).with("/repos/acme/api/git/commits/head-sha", token: "t").returns("tree" => { "sha" => "head-tree" })
      GithubApp.stubs(:post).with("/repos/acme/api/git/blobs", { content: "cG9vbA==", encoding: "base64" }, token: "t").returns("sha" => "blob-1")
      GithubApp.stubs(:post).with("/repos/acme/api/git/trees", { base_tree: "head-tree", tree: [ { path: "a.rb", mode: "100644", type: "blob", sha: "blob-1" } ] }, token: "t")
               .returns("sha" => "tree-1")
      GithubApp.expects(:post).with("/repos/acme/api/git/commits", { message: "Raise", tree: "tree-1", parents: [ "head-sha" ] }, token: "t").returns("sha" => "commit-2")
      GithubApp.expects(:write).with(:patch, "/repos/acme/api/git/refs/heads/team/fix%20pool", { sha: "commit-2", force: false }, token: "t").returns({})
      GithubApp.expects(:post).with { |path, *| path.end_with?("/pulls") }.never

      assert_equal "commit-2", GithubApp.push_commit("acme/api", branch: "team/fix pool", base_sha: "head-sha", message: "Raise",
                                                                 files: { "a.rb" => { mode: "100644", content: "cG9vbA==" } }, token: "t")
    end

    test "a change by any verb sends its body, reads GitHub's validation errors, and tells a missing thing from a refusal" do
      sent = []
      Http.stubs(:request).with { |_uri, request, **| sent << [ request.method, request.body ] }.returns(answer("204", {}))
      assert_equal({}, GithubApp.write(:delete, "/repos/acme/web/issues/5/labels/bug", token: "ghs_token"))
      assert_equal({}, GithubApp.write(:patch, "/repos/acme/web/pulls/5", { state: "closed" }, token: "ghs_token"))
      assert_equal [ [ "DELETE", nil ], [ "PATCH", { state: "closed" }.to_json ] ], sent

      Http.stubs(:request).returns(answer("422", message: "Validation Failed", errors: [ { message: "Reviews may only be requested from collaborators" } ]))
      assert_equal "GitHub answered 422: Validation Failed: Reviews may only be requested from collaborators",
                   assert_raises(GithubApp::Error) { GithubApp.write(:post, "/repos/acme/web/pulls/5/requested_reviewers", { reviewers: [ "x" ] }, token: "ghs_token") }.message

      Http.stubs(:request).returns(answer("404", message: "Not Found"))
      assert_raises(GithubApp::NotFound) { GithubApp.write(:put, "/repos/acme/web/pulls/5/merge", {}, token: "ghs_token") }
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

    test "a change marks a missing permission apart from any other refusal, and an answer with no body counts as done" do
      Http.stubs(:request).returns(stub(code: "403", body: { message: "Resource not accessible by integration" }.to_json))
      assert_raises(GithubApp::NotPermitted) { GithubApp.act("/repos/acme/web/actions/runs/41/cancel", token: "ghs_token") }

      Http.stubs(:request).returns(stub(code: "409", body: { message: "Cannot cancel a workflow run that is completed." }.to_json))
      error = assert_raises(GithubApp::Error) { GithubApp.act("/repos/acme/web/actions/runs/42/cancel", token: "ghs_token") }
      assert_not_kind_of GithubApp::NotPermitted, error
      assert_equal "GitHub answered 409: Cannot cancel a workflow run that is completed.", error.message

      Http.expects(:request).with do |uri, request, **|
        uri.to_s == "https://api.github.com/repos/acme/web/actions/runs/43/rerun" && request.body == "{}" && request["Authorization"] == "Bearer ghs_token"
      end.returns(stub(code: "201", body: ""))
      assert_equal({}, GithubApp.act("/repos/acme/web/actions/runs/43/rerun", {}, token: "ghs_token"))
    end

    def cache_token(value)
      @row.update!(credentials: { GithubApp::TOKEN_CACHE_KEY => { "token" => value, "expires_at" => 30.minutes.from_now.iso8601 } }.to_json)
    end

    def minted(value, permissions = { "contents" => "read", "actions" => "read" })
      stub(code: "201", body: { token: value, expires_at: 1.hour.from_now.iso8601, permissions: permissions }.to_json)
    end

    def refused = answer("403", message: "Resource not accessible by integration")

    # An answer with no rate limit headers, which a 403 is checked for first.
    def answer(code, body) = stub(code: code, body: body.to_json).tap { |response| response.stubs(:[]).returns(nil) }

    def answered(body) = stub(code: "200", body: body.to_json)

    def authorized_with(sent) = ->(_uri, request, **) { sent << request["Authorization"] }

    test "a cached token GitHub refuses for a permission mints a fresh one, keeps it and its permissions, and tries once more" do
      cache_token("ghs_old")
      sent = []
      Http.stubs(:request).with { |uri, request, **| sent << [ uri.path, request["Authorization"] ] }
          .returns(refused).then.returns(minted("ghs_new", "actions" => "write")).then.returns(answered("ok" => true))

      assert_equal({ "ok" => true }, GithubApp.get("/repos/acme/web/actions/runs", token: GithubApp.installation_token(@row)))
      assert_equal [ "/repos/acme/web/actions/runs", "/app/installations/12345/access_tokens", "/repos/acme/web/actions/runs" ], sent.map(&:first)
      assert_equal [ "Bearer ghs_old", "Bearer ghs_new" ], [ sent.first.last, sent.last.last ]
      assert_equal "ghs_new", @row.reload.credentials_hash[GithubApp::TOKEN_CACHE_KEY]["token"]
      assert_equal({ "actions" => "write" }, @row.installation_access, "the fresh token's permissions are what the installation holds now")
    end

    test "a 401 on a cached token is tried once more with a fresh one, for a change too" do
      cache_token("ghs_old")
      Http.stubs(:request).returns(stub(code: "401", body: { message: "Bad credentials" }.to_json)).then.returns(minted("ghs_new"))
          .then.returns(stub(code: "202", body: ""))

      assert_equal({}, GithubApp.act("/repos/acme/web/actions/runs/41/cancel", token: GithubApp.installation_token(@row)))
    end

    test "a refusal after the fresh token is GitHub's answer, so nothing is minted a second time" do
      cache_token("ghs_old")
      Http.stubs(:request).returns(refused).then.returns(refused)
      GithubApp.expects(:mint_token).once.with(@row).returns("ghs_new")

      assert_raises(GithubApp::NotPermitted) { GithubApp.get("/repos/acme/web/actions/runs", token: GithubApp.installation_token(@row)) }
    end

    test "a token minted for this call is never minted again, and a plain token is never refreshed" do
      Http.stubs(:request).returns(minted("ghs_new")).then.returns(refused)
      token = GithubApp.installation_token(@row)
      GithubApp.expects(:mint_token).never

      assert_raises(GithubApp::NotPermitted) { GithubApp.get("/repos/acme/web/pulls", token: token) }
      Http.stubs(:request).returns(refused)
      assert_raises(GithubApp::NotPermitted) { GithubApp.get("/repos/acme/web/pulls", token: "ghs_plain") }
    end

    test "a GraphQL answer saying a permission is missing is refused as one, so it is tried once more with a fresh token" do
      cache_token("ghs_old")
      denied = answered(data: nil, errors: [ { message: "Resource not accessible by integration" } ])
      Http.stubs(:request).returns(denied).then.returns(minted("ghs_new")).then.returns(answered(data: { "repository" => nil }))

      assert_equal({ "repository" => nil }, GithubApp.graphql("query { x }", {}, token: GithubApp.installation_token(@row)))
    end

    test "the token never shows in what is printed of it" do
      cache_token("ghs_secret")

      assert_not_includes GithubApp.installation_token(@row).inspect, "ghs_secret"
    end

    test "forgetting the token drops only the cached token" do
      cache_token("ghs_old")

      GithubApp.forget_token!(@row)

      assert_nil @row.reload.credentials_hash[GithubApp::TOKEN_CACHE_KEY]
    end

    test "uninstalling deletes the installation with the App's JWT, and one already gone counts as removed" do
      sent = []
      Http.stubs(:request).with { |uri, request, **| sent << [ request.method, uri.path, request["Authorization"].to_s.start_with?("Bearer ey") ] }
          .returns(stub(code: "204", body: ""))

      assert GithubApp.uninstall(@row)
      assert_equal [ [ "DELETE", "/app/installations/12345", true ] ], sent

      Http.stubs(:request).returns(stub(code: "404", body: { message: "Not Found" }.to_json))
      assert GithubApp.uninstall(@row)

      Http.stubs(:request).returns(answer("403", message: "Forbidden"))
      assert_match "Forbidden", assert_raises(GithubApp::Error) { GithubApp.uninstall(@row) }.message
    end

    test "the installation is read with the App's JWT, and one GitHub no longer knows reads as gone" do
      Http.stubs(:request).returns(answered("account" => { "login" => "acme" }, "suspended_at" => nil))
      assert_equal "acme", GithubApp.installation(@row).dig("account", "login")

      Http.stubs(:request).returns(stub(code: "404", body: { message: "Not Found" }.to_json))
      assert_nil GithubApp.installation(@row)
    end
  end
end
