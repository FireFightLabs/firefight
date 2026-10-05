require "test_helper"

module Integrations
  class TinybirdApiTest < ActiveSupport::TestCase
    TOKEN = "p.eyJ1IjogIngifQ.secret".freeze

    setup do
      @api = TinybirdApi.new(TOKEN, region: "aws-us-west-2")
    end

    test "the token goes as a Bearer header to the region's own API host, and the answer comes back" do
      Http.expects(:request).with do |uri, request, **|
        uri.to_s == "https://api.us-west-2.aws.tinybird.co/v1/workspace" && request["Authorization"] == "Bearer #{TOKEN}"
      end.returns(response(200, { id: "w1", name: "analytics" }))

      assert_equal({ "id" => "w1", "name" => "analytics" }, @api.workspace)
    end

    test "a connection that names no region reaches Tinybird's default host, and a region Tinybird does not have is refused" do
      Http.expects(:request).with { |uri, _request, **| uri.to_s == "https://api.tinybird.co/v0/datasources" }.returns(response(200, { datasources: [ { name: "events" } ] }))

      assert_equal [ { "name" => "events" } ], TinybirdApi.new(TOKEN).datasources
      assert_raises(TinybirdApi::Error) { TinybirdApi.new(TOKEN, region: "mars") }
    end

    test "pipes are read with what each node reads, and a query goes in the body with Tinybird's JSON format" do
      Http.expects(:request).with { |uri, _request, **| uri.path == "/v0/pipes" && uri.query == "dependencies=true" }.returns(response(200, { pipes: [] }))
      Http.expects(:request).with do |uri, request, **|
        uri.path == "/v0/sql" && request.is_a?(Net::HTTP::Post) && JSON.parse(request.body) == { "q" => "SELECT 1 FORMAT JSON" }
      end.returns(response(200, { data: [ { "1" => 1 } ], rows: 1 }))

      assert_equal [], @api.pipes
      assert_equal 1, @api.query("SELECT 1")["rows"]
    end

    test "an endpoint is called by its name with its own parameters, escaped" do
      Http.expects(:request).with do |uri, _request, **|
        uri.path == "/v0/pipes/top%20pages.json" && URI.decode_www_form(uri.query).to_h == { "date_from" => "2026-10-01", "limit" => "5" }
      end.returns(response(200, { data: [] }))

      assert_equal [], @api.call_endpoint("top pages", { "date_from" => "2026-10-01", "limit" => 5 })["data"]
    end

    test "a refused token is its own error, without the token in the words, and being asked to slow down is a rate limit" do
      Http.stubs(:request).returns(response(403, { error: "invalid authentication token. Invalid token #{TOKEN}" }))
      error = assert_raises(TinybirdApi::Refused) { @api.workspace }
      assert_equal "Tinybird answered 403: invalid authentication token. Invalid token [REDACTED:tinybird_token]", error.message

      Http.stubs(:request).returns(response(429, { error: "Too many requests" }))
      assert_raises(Integrations::RateLimited) { @api.datasources }
    end

    private

    def response(code, body)
      stub(code: code.to_s, body: body.to_json)
    end
  end
end
