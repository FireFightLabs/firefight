require "test_helper"

module Integrations
  class ClickhouseApiTest < ActiveSupport::TestCase
    KEY = "Basic #{Base64.strict_encode64('key-id:key-secret')}".freeze

    setup do
      @api = ClickhouseApi.new(KEY)
    end

    test "a service is read with the key as it is held, and its result envelope is opened" do
      Http.expects(:request).with do |uri, request, **|
        uri.to_s == "https://api.clickhouse.cloud/v1/organizations/org-1/services/svc-1" && request.is_a?(Net::HTTP::Get) && request["Authorization"] == KEY
      end.returns(response(200, { status: 200, result: { id: "svc-1", numReplicas: 3 } }))

      assert_equal({ "id" => "svc-1", "numReplicas" => 3 }, @api.service("org-1", "svc-1"))
    end

    test "scaling is a PATCH of replicaScaling with the body as JSON, and a refused key is told apart" do
      Http.expects(:request).with do |uri, request, **|
        uri.path == "/v1/organizations/org-1/services/svc-1/replicaScaling" && request.is_a?(Net::HTTP::Patch) &&
          JSON.parse(request.body) == { "numReplicas" => 5 } && request["Content-Type"] == "application/json"
      end.returns(response(200, { result: { numReplicas: 5 } }))
      assert_equal({ "numReplicas" => 5 }, @api.replica_scaling("org-1", "svc-1", { "numReplicas" => 5 }))

      Http.expects(:request).returns(response(403, { status: 403, error: "Forbidden" }))
      error = assert_raises(ClickhouseApi::Refused) { @api.service("org-1", "svc-1") }
      assert_match "Forbidden", error.message
    end

    test "a state change is a PATCH of state with its command, and activities are read between two times" do
      Http.expects(:request).with do |uri, request, **|
        uri.path == "/v1/organizations/org-1/services/svc-1/state" && request.is_a?(Net::HTTP::Patch) && JSON.parse(request.body) == { "command" => "stop" }
      end.returns(response(200, { result: { state: "stopping" } }))
      assert_equal({ "state" => "stopping" }, @api.state("org-1", "svc-1", "stop"))

      Http.expects(:request).with do |uri, request, **|
        uri.path == "/v1/organizations/org-1/activities" && request.is_a?(Net::HTTP::Get) &&
          URI.decode_www_form(uri.query).to_h == { "from_date" => "2026-10-01T00:00:00Z", "to_date" => "2026-10-02T00:00:00Z" }
      end.returns(response(200, { result: [ { id: "a1", type: "service_stop" } ] }))
      assert_equal [ { "id" => "a1", "type" => "service_stop" } ], @api.activities("org-1", from: "2026-10-01T00:00:00Z", to: "2026-10-02T00:00:00Z")

      Http.expects(:request).with { |uri, _request, **| uri.path == "/v1/organizations/org-1/activities/a1" && uri.query.nil? }
          .returns(response(200, { result: { id: "a1" } }))
      assert_equal({ "id" => "a1" }, @api.activity("org-1", "a1"))
    end

    private

    def response(code, body)
      stub(code: code.to_s, body: body.to_json, each_header: [].each, to_hash: {})
    end
  end
end
