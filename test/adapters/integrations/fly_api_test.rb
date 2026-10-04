require "test_helper"

module Integrations
  class FlyApiTest < ActiveSupport::TestCase
    test "a token from fly tokens create goes under FlyV1, a pasted scheme is kept, and anything else goes under Bearer" do
      assert_equal "FlyV1 fm2_abc,fm2_def", FlyApi.new("fm2_abc,fm2_def").authorization
      assert_equal "FlyV1 fm2_abc", FlyApi.new(" FlyV1 fm2_abc ").authorization
      assert_equal "Bearer personal", FlyApi.new("personal").authorization
    end

    test "apps are listed for the organization on the Machines API, with the token" do
      Http.expects(:request).with do |uri, request, **|
        uri.host == "api.machines.dev" && uri.path == "/v1/apps" && URI.decode_www_form(uri.query).include?([ "org_slug", "acme" ]) &&
          request["Authorization"] == "FlyV1 fm2_x"
      end.returns(response(200, { apps: [ { name: "web" } ], total_apps: 1 }))

      assert_equal [ "web" ], FlyApi.new("fm2_x").apps("acme").map { |app| app["name"] }
    end

    test "releases come from GraphQL, and an answer with only errors is raised in Fly's words" do
      Http.expects(:request).with do |uri, request, **|
        uri.to_s == "https://api.fly.io/graphql" && JSON.parse(request.body)["variables"] == { "appName" => "web", "limit" => 5 }
      end.returns(response(200, { data: { app: { releases: { nodes: [ { version: 3 } ] } } } }))
      assert_equal [ { "version" => 3 } ], FlyApi.new("t").releases("web", limit: 5)

      Http.stubs(:request).returns(response(200, { errors: [ { message: "Could not find App" } ] }))
      assert_equal "Fly answered: Could not find App", assert_raises(FlyApi::Error) { FlyApi.new("t").releases("web", limit: 5) }.message
    end

    test "a metrics query goes to the organization's Prometheus, and its error is raised" do
      Http.expects(:request).with do |uri, *|
        query = URI.decode_www_form(uri.query).to_h
        uri.path == "/prometheus/acme/api/v1/query_range" && query["step"] == "60" && query["query"] == "up"
      end.returns(response(200, { status: "success", data: { result: [ { metric: {}, values: [ [ 1, "2" ] ] } ] } }))
      assert_equal 1, FlyApi.new("t").query_range("acme", query: "up", start: Time.zone.at(0), finish: Time.zone.at(3600), step: 60).size

      Http.stubs(:request).returns(response(200, { status: "error", errorType: "bad_data", error: "parse error" }))
      assert_raises(FlyApi::Error) { FlyApi.new("t").query_range("acme", query: "(", start: Time.zone.at(0), finish: Time.zone.at(1), step: 60) }
    end

    test "a machine update carries its whole config and version, and a refused version, a slow down and a refusal are told apart" do
      Http.expects(:request).with do |uri, request, **|
        uri.path == "/v1/apps/web/machines/m1" && JSON.parse(request.body) == { "config" => { "image" => "img:2" }, "current_version" => "v9" }
      end.returns(response(200, { id: "m1" }))
      FlyApi.new("t").update_machine("web", "m1", config: { "image" => "img:2" }, current_version: "v9")

      Http.stubs(:request).returns(response(409, { error: "version mismatch" }))
      assert_raises(FlyApi::Conflict) { FlyApi.new("t").restart_machine("web", "m1") }
      Http.stubs(:request).returns(response(429, {}))
      assert_raises(FlyApi::RateLimited) { FlyApi.new("t").app("web") }
      Http.stubs(:request).returns(response(401, { error: "unauthorized" }))
      assert_equal "Fly answered 401: unauthorized", assert_raises(FlyApi::Error) { FlyApi.new("t").app("web") }.message
    end

    private

    def response(code, body)
      stub(code: code.to_s, body: body.to_json)
    end
  end
end
