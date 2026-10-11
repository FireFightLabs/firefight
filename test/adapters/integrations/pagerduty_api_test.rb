require "test_helper"

module Integrations
  class PagerdutyApiTest < ActiveSupport::TestCase
    HEADERS = { "Authorization" => "Token token=pd-key" }.freeze

    test "an incident is opened on the service with its body and key, versioned and with the connection's own credentials" do
      Http.expects(:request).with do |uri, request, **|
        body = JSON.parse(request.body)
        uri.host == "api.pagerduty.com" && uri.path == "/incidents" && request.is_a?(Net::HTTP::Post) &&
          request["Authorization"] == "Token token=pd-key" && request["Accept"] == PagerdutyApi::ACCEPT && request["From"].nil? &&
          body == { "incident" => { "type" => "incident", "title" => "INC-001 Checkout failing", "service" => { "id" => "PF9KMXH", "type" => "service_reference" },
                                    "body" => { "type" => "incident_body", "details" => "Halon looked" }, "incident_key" => "firefight-page-1" } }
      end.returns(response(201, { incident: { id: "PGR0VU2", incident_number: 42 } }))

      incident = PagerdutyApi.new(HEADERS).create_incident(service_id: "PF9KMXH", title: "INC-001 Checkout failing", details: "Halon looked",
                                                           incident_key: "firefight-page-1")

      assert_equal "PGR0VU2", incident["id"]
    end

    test "a status change goes to the incident on the EU service region's API" do
      Http.expects(:request).with do |uri, request, **|
        uri.host == "api.eu.pagerduty.com" && uri.path == "/incidents/PGR0VU2" && request.is_a?(Net::HTTP::Put) &&
          JSON.parse(request.body) == { "incident" => { "type" => "incident_reference", "status" => "acknowledged" } }
      end.returns(response(200, { incident: { id: "PGR0VU2", status: "acknowledged" } }))

      assert_equal "acknowledged", PagerdutyApi.new(HEADERS, region: PagerdutyApi::REGION_EU).update_status("PGR0VU2", status: "acknowledged")["status"]
    end

    test "who is on call is asked once for each person and level, with their emails" do
      Http.expects(:request).with do |uri, *|
        uri.path == "/oncalls" && URI.decode_www_form(uri.query) == [ [ "include[]", "users" ], [ "earliest", "true" ], [ "limit", "100" ] ]
      end.returns(response(200, { oncalls: [ { user: { email: "bob@example.com" } } ] }))

      assert_equal [ { "user" => { "email" => "bob@example.com" } } ], PagerdutyApi.new(HEADERS).on_calls
    end

    test "PagerDuty's refusal is raised with its message and the field it names, and a missing incident is a not found" do
      Http.stubs(:request).returns(response(400, { error: { message: "Invalid Input Provided", code: 2001, errors: [ "Service not found" ] } }))
      error = assert_raises(PagerdutyApi::Error) { PagerdutyApi.new(HEADERS).service("PNOPE") }
      assert_equal "PagerDuty answered 400: Invalid Input Provided. Service not found", error.message

      Http.stubs(:request).returns(response(404, { error: { message: "Not Found" } }))
      assert_kind_of Integrations::NotFound, assert_raises(PagerdutyApi::Error) { PagerdutyApi.new(HEADERS).incident("PNOPE") }
      assert_raises(PagerdutyApi::Error) { PagerdutyApi.new(HEADERS, region: "ap") }
    end

    private

    def response(code, body)
      stub(code: code.to_s, body: body.to_json)
    end
  end
end
