require "test_helper"

class CodeAgentGitControllerTest < ActionDispatch::IntegrationTest
  OLD = "a" * 40
  NEW = "b" * 40

  setup do
    @workspace = workspaces(:slack_workspace_one)
    github = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
    @row = github.integration_environments.create!(base_config: { "installation_id" => "12345" })
    @session, @token = CodeAgentSession.open!(workspace: @workspace, choice: FirefightAi::ModelChoice.new(model: "claude-sonnet-4-5", provider: "anthropic"),
                                              repository: "acme/api")
    @session.update_columns(integration_environment_id: @row.id, git_branch: "halon/fix-1")
    Integrations::GithubApp.stubs(:installation_token).returns("ghs_installation")
  end

  test "a push to the session's branch streams to the code host byte for byte, with the connection's credential, and its answer streams back" do
    body = pkt("#{OLD} #{NEW} refs/heads/halon/fix-1\0report-status\n") + "0000" + "PACK\x00\x00\x00\x02#{'x' * 5000}".b
    sent = nil
    Integrations::GitHttp.expects(:forward).with do |remote, repository, path, method:, body:, length:, headers:|
      sent = body.read
      remote.url(repository) == "https://github.com/acme/api.git" && remote.user == "x-access-token" && remote.token.call == "ghs_installation" &&
        path == Integrations::GitGate::RECEIVE && method == :post && length == sent.bytesize && headers["Content-Type"] == "application/x-git-receive-pack-request"
    end.multiple_yields([ :start, 200, { "content-type" => "application/x-git-receive-pack-result" } ], [ :chunk, "000eunpack ok\n0000" ])

    post "/code_agent/git/change.git/git-receive-pack", params: body, headers: git_headers("application/x-git-receive-pack-request")

    assert_response :success
    assert_equal body, sent, "the pack behind the commands is passed on unread"
    assert_equal "000eunpack ok\n0000", response.body
    assert_equal "application/x-git-receive-pack-result", response.media_type
  end

  test "a push to main, another branch, a tag or a delete is refused before anything reaches the code host" do
    Integrations::GitHttp.expects(:forward).never
    [ "#{OLD} #{NEW} refs/heads/main", "#{OLD} #{NEW} refs/heads/feature", "#{'0' * 40} #{NEW} refs/tags/v1", "#{OLD} #{'0' * 40} refs/heads/halon/fix-1" ].each do |command|
      post "/code_agent/git/change.git/git-receive-pack", params: pkt("#{command}\0report-status\n") + "0000PACK", headers: git_headers("application/x-git-receive-pack-request")

      assert_response :forbidden
      assert_match "A code change", response.body
    end
  end

  test "fetching reads the session's repository, and what git asks for first is passed through with its protocol" do
    Integrations::GitHttp.expects(:forward).with do |remote, repository, path, method:, headers:, **|
      remote.url(repository) == "https://github.com/acme/api.git" && path == "info/refs?service=git-upload-pack" && method == :get && headers["Git-Protocol"] == "version=2"
    end.multiple_yields([ :start, 200, { "content-type" => "application/x-git-upload-pack-advertisement" } ], [ :chunk, "001e# service=git-upload-pack\n" ])

    get "/code_agent/git/change.git/info/refs", params: { service: "git-upload-pack" }, headers: git_headers(nil).merge("Git-Protocol" => "version=2")

    assert_response :success
    assert_equal "001e# service=git-upload-pack\n", response.body
  end

  test "no token, an ended session, an unknown service or a request too large never reaches the code host" do
    Integrations::GitHttp.expects(:forward).never

    get "/code_agent/git/change.git/info/refs", params: { service: "git-upload-pack" }
    assert_response :unauthorized
    assert_equal 'Basic realm="Firefight"', response.headers["WWW-Authenticate"]

    get "/code_agent/git/change.git/info/refs", params: { service: "git-shell" }, headers: git_headers(nil)
    assert_response :forbidden

    post "/code_agent/git/change.git/git-upload-pack", params: "x", headers: git_headers("application/x-git-upload-pack-request")
                                                                              .merge("CONTENT_LENGTH" => (Integrations::GitGate::MAX_UPLOAD_BYTES + 1).to_s)
    assert_response :content_too_large

    @session.close!
    get "/code_agent/git/change.git/info/refs", params: { service: "git-upload-pack" }, headers: git_headers(nil)
    assert_response :unauthorized
  end

  private

  def git_headers(content_type)
    { "Authorization" => "Basic #{Base64.strict_encode64("halon:#{@token}")}", "CONTENT_TYPE" => content_type }.compact
  end

  def pkt(line) = format("%04x", line.bytesize + 4) + line
end
