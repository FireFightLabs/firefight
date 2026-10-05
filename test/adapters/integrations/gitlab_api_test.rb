require "test_helper"

module Integrations
  class GitlabApiTest < ActiveSupport::TestCase
    def response(code, body = "", headers = {})
      answer = Net::HTTPResponse::CODE_TO_OBJ.fetch(code.to_s).new("1.1", code.to_s, "")
      answer.instance_variable_set(:@body, body.is_a?(String) ? body : body.to_json)
      answer.instance_variable_set(:@read, true)
      headers.each { |name, value| answer[name] = value }
      answer
    end

    test "the address is GitLab.com when blank, an instance's own without its API path, and only ever https" do
      assert_equal "https://gitlab.com", GitlabApi.base_url("")
      assert_equal "https://gitlab.example.com/gitlab", GitlabApi.base_url(" https://gitlab.example.com/gitlab/api/v4/ ")
      assert_match "must start with https", assert_raises(GitlabApi::Error) { GitlabApi.base_url("http://gitlab.example.com") }.message
      assert_match "without a query or credentials", assert_raises(GitlabApi::Error) { GitlabApi.base_url("https://user:pass@gitlab.example.com") }.message
    end

    test "a call carries the token, encodes a project's path as one segment and a list once per value" do
      sent = nil
      Http.stubs(:request).with { |uri, request, **options| sent = [ uri, request, options ] }.returns(response(200, [ { "id" => 1 } ]))

      GitlabApi.new("", "glpat-x").get("#{GitlabApi.project('acme/platform/web')}/jobs", "scope" => [ "failed" ], "per_page" => 5)

      uri, request, options = sent
      assert_equal "/api/v4/projects/acme%2Fplatform%2Fweb/jobs", uri.path
      assert_equal "scope%5B%5D=failed&per_page=5", uri.query
      assert_equal "glpat-x", request["PRIVATE-TOKEN"]
      assert_nil options[:ipaddr], "GitLab.com is GitLab's own, so its address is not pinned"
    end

    test "an instance of a workspace's own is reached at the public address it was checked at, and a private one is refused" do
      Addrinfo.stubs(:getaddrinfo).with("gitlab.example.com", nil, nil, :STREAM).returns([ stub(ip_address: "203.0.113.7") ])
      Http.expects(:request).with { |_uri, _request, **options| options[:ipaddr] == "203.0.113.7" }.returns(response(200, {}))
      GitlabApi.new("https://gitlab.example.com", "t").get("/projects")

      Addrinfo.stubs(:getaddrinfo).with("gitlab.internal", nil, nil, :STREAM).returns([ stub(ip_address: "10.0.0.5") ])
      error = assert_raises(GitlabApi::Error) { GitlabApi.new("https://gitlab.internal", "t").get("/projects") }
      assert_equal "gitlab.internal is on a private network, which Firefight does not connect to.", error.message

      ENV["INTEGRATION_GITLAB_PRIVATE_HOSTS"] = "gitlab.internal"
      Http.expects(:request).with { |_uri, _request, **options| options[:ipaddr] == "10.0.0.5" }.returns(response(200, {}))
      GitlabApi.new("https://gitlab.internal", "t").get("/projects")
    ensure
      ENV.delete("INTEGRATION_GITLAB_PRIVATE_HOSTS")
    end

    test "a refusal, a missing thing and being asked to slow down each raise their own error with GitLab's words" do
      Http.stubs(:request).returns(response(401, { "message" => "401 Unauthorized" }))
      assert_raises(GitlabApi::Refused) { GitlabApi.new("", "t").get("/projects") }
      Http.stubs(:request).returns(response(404, { "message" => "404 Project Not Found" }))
      assert_equal "GitLab answered 404: 404 Project Not Found", assert_raises(GitlabApi::NotFound) { GitlabApi.new("", "t").get("/projects/x") }.message
      Http.stubs(:request).returns(response(429, "Retry later"))
      assert_raises(Integrations::RateLimited) { GitlabApi.new("", "t").get("/projects") }
    end

    test "a list follows GitLab's next page header as far as it was asked, and says when more were left" do
      pages = { "1" => response(200, [ { "id" => 1 } ], "x-next-page" => "2"), "2" => response(200, [ { "id" => 2 } ], "x-next-page" => "3") }
      Http.stubs(:request).with { |uri, *| true }.returns(pages["1"]).then.returns(pages["2"])

      items, more = GitlabApi.new("", "t").list("/projects", {}, pages: 2)

      assert_equal [ 1, 2 ], items.map { |item| item["id"] }
      assert more
    end

    test "a job's log is read as text, and only its end is kept" do
      Http.stubs(:request).returns(response(200, "line one\nfailed here\n"))

      assert_equal "line one\nfailed here\n", GitlabApi.new("", "glpat-x").text("/projects/1/jobs/2/trace")
    end
  end
end
