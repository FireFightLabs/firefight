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

    private

    def response(code, body)
      stub(code: code.to_s, body: body.to_json)
    end
  end
end
