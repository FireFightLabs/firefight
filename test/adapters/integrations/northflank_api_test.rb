require "test_helper"

module Integrations
  class NorthflankApiTest < ActiveSupport::TestCase
    setup do
      @api = NorthflankApi.new("nf-token")
    end

    test "a list parameter is sent once per value, with the token, and the data comes back" do
      Http.expects(:request).with do |uri, request, **|
        query = URI.decode_www_form(uri.query)
        uri.path == "/v1/projects/firefight/services/web/metrics" && request["Authorization"] == "Bearer nf-token" &&
          query.count { |name, _| name == "metricTypes" } == 2 && query.include?([ "queryType", "range" ])
      end.returns(response(200, { data: { cpu: { values: [] } } }))

      data = @api.metrics("firefight", "services", "web", { "metricTypes" => %w[cpu memory], "startTime" => "2026-09-25T14:00:00Z" })

      assert_equal({ "cpu" => { "values" => [] } }, data)
    end

    test "Northflank's refusal is raised with its own reason" do
      Http.stubs(:request).returns(response(403, { error: { message: "Missing permission: View Observability" } }))

      error = assert_raises(NorthflankApi::Error) { @api.project("firefight") }

      assert_equal "Northflank answered 403: Missing permission: View Observability", error.message
    end

    test "data kept behind a Northflank feature the account does not have is its own refusal, not a bad token" do
      Http.stubs(:request).returns(response(401, { error: { message: "Feature flag is not enabled for your account 2" } }))

      error = assert_raises(NorthflankApi::NotEnabled) { @api.logs("firefight", "services", "web", { "type" => "ingress" }) }

      assert_equal "Northflank answered 401: Feature flag is not enabled for your account 2", error.message

      Http.stubs(:request).returns(response(500, { error: { message: "Feature flag is not enabled for your account" } }))
      assert_not_kind_of NorthflankApi::NotEnabled, assert_raises(NorthflankApi::Error) { @api.logs("firefight", "services", "web", {}) }
    end

    test "a change is sent with its method, the token and its body as JSON" do
      Http.expects(:request).with do |uri, request, **|
        uri.path == "/v1/projects/firefight/services/web/scale" && request.is_a?(Net::HTTP::Post) &&
          request["Authorization"] == "Bearer nf-token" && JSON.parse(request.body) == { "instances" => 2 }
      end.returns(response(200, { data: {} }))

      assert_equal({ "data" => {} }, @api.request("POST", "firefight", "services/web/scale", { "instances" => 2 }))
    end

    test "a change Northflank accepted stays accepted when what came back is not JSON" do
      Http.stubs(:request).returns(stub(code: "200", body: "OK"))

      assert_equal({}, @api.request("POST", "firefight", "services/web/restart"))
    end

    private

    def response(code, body)
      stub(code: code.to_s, body: body.to_json)
    end
  end
end
