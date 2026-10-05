require "test_helper"

module Integrations
  class BitbucketApiTest < ActiveSupport::TestCase
    setup do
      @api = BitbucketApi.new("bb-token")
    end

    test "a call goes to Bitbucket's API with the token as a bearer token" do
      Http.expects(:request).with do |uri, request, **options|
        uri.to_s == "https://api.bitbucket.org/2.0/repositories/acme/web?pagelen=1" && request["Authorization"] == "Bearer bb-token" && options[:ipaddr].nil?
      end.returns(response(200, { full_name: "acme/web" }))

      assert_equal "acme/web", @api.get(BitbucketApi.repository("acme/web"), "pagelen" => 1)["full_name"]
    end

    test "a list follows next on Bitbucket's API, and says when more were left" do
      first = response(200, { values: [ { slug: "a" } ], next: "https://api.bitbucket.org/2.0/repositories/acme?page=2" })
      second = response(200, { values: [ { slug: "b" } ], next: "https://api.bitbucket.org/2.0/repositories/acme?page=3" })
      Http.stubs(:request).returns(first).then.returns(second)

      items, more = @api.list("/repositories/acme", {}, pages: 2)

      assert_equal %w[a b], items.map { |item| item["slug"] }
      assert more
    end

    test "a next page somewhere other than Bitbucket's API is refused" do
      Http.stubs(:request).returns(response(200, { values: [], next: "https://evil.example/steal" }))

      assert_raises(BitbucketApi::Error) { @api.list("/repositories/acme", {}, pages: 2) }
    end

    test "a step log kept elsewhere is followed without the token" do
      redirect = Net::HTTPTemporaryRedirect.new("1.1", "307", "Temporary Redirect")
      redirect["location"] = "https://logs.example.net/step.log"
      Addrinfo.stubs(:getaddrinfo).with("logs.example.net", nil, nil, :STREAM).returns([ stub(ip_address: "203.0.113.9") ])
      Http.expects(:request).with { |uri, request, **| uri.host == "api.bitbucket.org" && request["Authorization"] == "Bearer bb-token" }.returns(redirect)
      Http.expects(:request).with { |uri, request, **options| uri.host == "logs.example.net" && request["Authorization"].nil? && options[:ipaddr] == "203.0.113.9" }
          .returns(stub(code: "200", body: "line one\nline two"))

      assert_equal "line one\nline two", @api.text("/repositories/acme/web/pipelines/%7Bp%7D/steps/%7Bs%7D/log")
    end

    test "Bitbucket's answers are raised by kind, with its own reason" do
      Http.stubs(:request).returns(response(401, { error: { message: "Token is invalid" } }))
      assert_equal "Bitbucket answered 401: Token is invalid", assert_raises(BitbucketApi::Refused) { @api.get("/user") }.message

      Http.stubs(:request).returns(response(404, { error: { message: "Repository not found" } }))
      assert_raises(BitbucketApi::NotFound) { @api.get("/repositories/acme/gone") }

      Http.stubs(:request).returns(response(429, {}))
      assert_raises(Integrations::RateLimited) { @api.get("/repositories/acme") }
    end

    test "a change is posted as JSON with the token, and an answer with no body counts as done" do
      Http.expects(:request).with do |uri, request, **|
        uri.to_s == "https://api.bitbucket.org/2.0/repositories/acme/web/pipelines/" && request.method == "POST" &&
          request["Authorization"] == "Bearer bb-token" && JSON.parse(request.body) == { "target" => { "ref_name" => "main" } }
      end.returns(response(201, { build_number: 8 }))
      assert_equal 8, @api.post("/repositories/acme/web/pipelines/", "target" => { "ref_name" => "main" })["build_number"]

      Http.expects(:request).with { |uri, request, **| uri.path.end_with?("/stopPipeline") && request.body.nil? }.returns(stub(code: "204", body: ""))
      assert_equal({}, @api.post("/repositories/acme/web/pipelines/%7Bp%7D/stopPipeline"))
    end

    test "a path keeps its slashes and escapes the rest" do
      assert_equal "infra/my%20file%23.tf", BitbucketApi.path("infra/my file#.tf")
    end

    private

    def response(code, body) = stub(code: code.to_s, body: body.to_json)
  end
end
