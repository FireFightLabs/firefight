require "test_helper"

module Integrations
  class AzureDevopsApiTest < ActiveSupport::TestCase
    def response(code, body = "", headers = {})
      answer = Net::HTTPResponse::CODE_TO_OBJ.fetch(code.to_s).new("1.1", code.to_s, "")
      answer.instance_variable_set(:@body, body.is_a?(String) ? body : body.to_json)
      answer.instance_variable_set(:@read, true)
      headers.each { |name, value| answer[name] = value }
      answer
    end

    test "a call signs in with the token as Basic with an empty user, under the organization, at api-version 7.1 unless asked otherwise" do
      sent = nil
      Http.stubs(:request).with { |uri, request, **| sent = [ uri, request ] }.returns(response(200, { "count" => 0, "value" => [] }))

      AzureDevopsApi.new("fabrikam", "pat").get("#{AzureDevopsApi.project('Fabrikam Fiber')}/_apis/build/builds", "$top" => 5)

      uri, request = sent
      assert_equal "dev.azure.com", uri.host
      assert_equal "/fabrikam/Fabrikam%20Fiber/_apis/build/builds", uri.path
      assert_equal "api-version=7.1&%24top=5", uri.query
      assert_equal "Basic #{Base64.strict_encode64(':pat')}", request["Authorization"]

      AzureDevopsApi.new("fabrikam", "pat").get("/Shop/_apis/policy/evaluations", "api-version" => "7.1-preview.1")
      assert_equal "api-version=7.1-preview.1", sent.first.query
    end

    test "a classic release path is read on the Release API's own host" do
      sent = nil
      Http.stubs(:request).with { |uri, *| sent = uri }.returns(response(200, { "value" => [] }))

      AzureDevopsApi.new("fabrikam", "pat").get("/Shop/_apis/release/deployments")

      assert_equal "https://vsrm.dev.azure.com/fabrikam/Shop/_apis/release/deployments?api-version=7.1", sent.to_s
    end

    test "an organization is its name alone" do
      assert_match "organization is its name", assert_raises(AzureDevopsApi::Error) { AzureDevopsApi.new("fabrikam/Shop", "pat") }.message
      assert_match "organization is its name", assert_raises(AzureDevopsApi::Error) { AzureDevopsApi.new("", "pat") }.message
    end

    test "a refusal, the sign in page, a missing thing and being asked to slow down each raise their own error with Azure DevOps' words" do
      Http.stubs(:request).returns(response(401, { "message" => "TF400813: The user is not authorized" }))
      assert_equal "Azure DevOps answered 401: TF400813: The user is not authorized",
                   assert_raises(AzureDevopsApi::Refused) { AzureDevopsApi.new("fabrikam", "t").get("/_apis/projects") }.message
      Http.stubs(:request).returns(response(203, "<html>Sign in</html>"))
      assert_match "did not accept this token", assert_raises(AzureDevopsApi::Refused) { AzureDevopsApi.new("fabrikam", "t").get("/_apis/projects") }.message
      Http.stubs(:request).returns(response(404, { "message" => "TF200016: The project does not exist" }))
      assert_raises(AzureDevopsApi::NotFound) { AzureDevopsApi.new("fabrikam", "t").get("/_apis/projects/x") }
      Http.stubs(:request).returns(response(429, "slow down"))
      assert_raises(Integrations::RateLimited) { AzureDevopsApi.new("fabrikam", "t").get("/_apis/projects") }
    end

    test "a list reads on from each page's continuation token as far as it was asked, and says when more were left" do
      queries = []
      Http.stubs(:request).with { |uri, *| queries << uri.query }
          .returns(response(200, { "value" => [ { "id" => 1 } ] }, "x-ms-continuationtoken" => "next-1"))
          .then.returns(response(200, { "value" => [ { "id" => 2 } ] }, "x-ms-continuationtoken" => "next-2"))

      items, more = AzureDevopsApi.new("fabrikam", "t").list("/Shop/_apis/build/definitions", { "$top" => 100 }, pages: 2)

      assert_equal [ 1, 2 ], items.map { |item| item["id"] }
      assert more
      assert_equal [ "api-version=7.1&%24top=100", "api-version=7.1&%24top=100&continuationToken=next-1" ], queries
    end

    test "a change is sent with its body as JSON, and a log is read as text" do
      sent = nil
      Http.stubs(:request).with { |uri, request, **| sent = [ uri.to_s, request ] }.returns(response(200, { "id" => 7, "status" => "inProgress" }))

      assert_equal 7, AzureDevopsApi.new("fabrikam", "t").patch("/Shop/_apis/build/builds/7", {}, "retry" => true)["id"]
      assert_equal "https://dev.azure.com/fabrikam/Shop/_apis/build/builds/7?api-version=7.1&retry=true", sent.first
      assert_equal [ "PATCH", "application/json", {} ], [ sent.last.method, sent.last["Content-Type"], JSON.parse(sent.last.body) ]

      Http.unstub(:request)
      Http.expects(:request).with { |_uri, request, **| request["Accept"] == "text/plain" }.returns(response(200, "2026-10-01T10:00:00Z ##[error]Tests failed\n"))
      assert_equal "2026-10-01T10:00:00Z ##[error]Tests failed\n", AzureDevopsApi.new("fabrikam", "t").text("/Shop/_apis/build/builds/7/logs/12")
    end
  end
end
