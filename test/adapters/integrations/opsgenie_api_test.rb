require "test_helper"

module Integrations
  class OpsgenieApiTest < ActiveSupport::TestCase
    test "a read goes to the account's instance with the key as a GenieKey and its query, and the data comes back" do
      Http.expects(:request).with do |uri, request, **|
        query = URI.decode_www_form(uri.query).to_h
        uri.host == "api.eu.opsgenie.com" && uri.path == "/v2/alerts" && request["Authorization"] == "GenieKey og-key" &&
          query == { "query" => "status: open", "limit" => "100", "sort" => "createdAt", "order" => "desc" }
      end.returns(response(200, { data: [ { id: "a1" } ], took: 0.1 }))

      assert_equal [ { "id" => "a1" } ], OpsgenieApi.new("og-key", region: OpsgenieApi::REGION_EU).alerts(query: "status: open", limit: 500)
    end

    test "an action is posted as JSON with Firefight as its source, and a name never reaches another path" do
      Http.expects(:request).with do |uri, request, **|
        body = JSON.parse(request.body)
        uri.path == "/v2/alerts/db%2Fdown/escalate" && URI.decode_www_form(uri.query).to_h == { "identifierType" => "alias" } &&
          body == { "escalation" => { "name" => "ops_escalation" }, "note" => "Paging the database owners", "source" => "Firefight" }
      end.returns(response(202, { result: "Request will be processed", requestId: "r1" }))

      accepted = OpsgenieApi.new("og-key").escalate("db/down", "alias", escalation: "ops_escalation", by_name: true, note: "Paging the database owners")

      assert_equal "r1", accepted["requestId"]
    end

    test "Opsgenie's refusal is raised with its own reason, and a key it does not know is its own error" do
      Http.stubs(:request).returns(response(403, { message: "You are not authorized for this request" }))
      error = assert_raises(OpsgenieApi::Error) { OpsgenieApi.new("og-key").account }
      assert_equal "Opsgenie answered 403: You are not authorized for this request", error.message

      Http.stubs(:request).returns(response(401, { message: "Could not authenticate" }))
      assert_raises(OpsgenieApi::Unauthenticated) { OpsgenieApi.new("og-key").account }
      Http.stubs(:request).returns(response(429, { message: "Too many requests" }))
      assert_kind_of Integrations::RateLimited, assert_raises(OpsgenieApi::Error) { OpsgenieApi.new("og-key").schedules }
    end

    private

    def response(code, body)
      stub(code: code.to_s, body: body.to_json)
    end
  end
end
