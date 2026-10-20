require "test_helper"

module Integrations
  class ConvexApiTest < ActiveSupport::TestCase
    setup do
      @api = ConvexApi.new("https://happy-animal-123.convex.cloud/", "prod:happy-animal-123|secret")
    end

    test "the deploy key goes as Convex's own scheme, to the deployment's API, and the answer comes back" do
      Http.expects(:request).with do |uri, request, **|
        uri.to_s == "https://happy-animal-123.convex.cloud/api/v1/deployment_info" && request["Authorization"] == "Convex prod:happy-animal-123|secret"
      end.returns(response(200, { kind: "cloud", deploymentType: "prod" }))

      assert_equal({ "kind" => "cloud", "deploymentType" => "prod" }, @api.deployment_info)
    end

    test "audit log events and function logs are read with their own parameters" do
      Http.expects(:request).with do |uri, _request, **|
        uri.path == "/api/v1/list_audit_log_events" && URI.decode_www_form(uri.query).to_h == { "from" => "1000", "limit" => "100" }
      end.returns(response(200, { items: [], pagination: { hasMore: false } }))
      Http.expects(:request).with { |uri, _request, **| uri.path == "/api/stream_function_logs" && uri.query == "cursor=5000" }
          .returns(response(200, { entries: [], newCursor: 5000 }))

      assert_equal [], @api.audit_log(from: 1000)["items"]
      assert_equal 5000, @api.function_logs(cursor: 5000)["newCursor"]
    end

    test "Convex's refusal is raised with its own reason, and being asked to slow down is its own error" do
      Http.stubs(:request).returns(response(401, { code: "BadDeployKey", message: "The provided deploy key was invalid" }))
      error = assert_raises(ConvexApi::Error) { @api.deployment_info }
      assert_equal "Convex answered 401: The provided deploy key was invalid. Check that the deploy key belongs to this deployment " \
                   "and has not been revoked.", error.message

      Http.stubs(:request).returns(response(429, {}))
      assert_raises(Integrations::RateLimited) { @api.canonical_urls }
    end

    test "pausing, unpausing and the webhook log stream post to the paths Convex's spec gives, with the key" do
      Http.expects(:request).with { |uri, request, **| uri.path == "/api/v1/pause_deployment" && request.method == "POST" && request["Authorization"].start_with?("Convex ") }
          .returns(response(200, {}))
      Http.expects(:request).with { |uri, request, **| uri.path == "/api/v1/unpause_deployment" && request.method == "POST" }.returns(response(200, {}))
      Http.expects(:request).with do |uri, request, **|
        uri.path == "/api/v1/create_log_stream" &&
          JSON.parse(request.body) == { "logStreamType" => "webhook", "url" => "https://ff.test/hook", "format" => "json", "topics" => [ "audit_log" ] }
      end.returns(response(200, { id: "ls1", hmacSecret: "s3cret", logStreamType: "webhook" }))
      Http.expects(:request).with { |uri, request, **| uri.path == "/api/v1/delete_log_stream/ls1" && request.method == "POST" }.returns(response(200, {}))
      Http.expects(:request).with { |uri, _request, **| uri.path == "/api/v1/list_usage_limits" }.returns(response(200, { usageLimits: [ { id: "l1" } ] }))

      @api.pause
      @api.unpause
      assert_equal "s3cret", @api.create_webhook_stream(url: "https://ff.test/hook", topics: [ "audit_log" ])["hmacSecret"]
      @api.delete_log_stream("ls1")
      assert_equal [ { "id" => "l1" } ], @api.usage_limits
    end

    private

    def response(code, body)
      stub(code: code.to_s, body: body.to_json)
    end
  end
end
