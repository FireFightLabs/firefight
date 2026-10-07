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

    test "a list is read a page at a time from Northflank's cursor, and one past the page bound says it was cut short" do
      Http.expects(:request).with { |uri, _| URI.decode_www_form(uri.query).to_h == { "per_page" => "100" } }
          .returns(response(200, { data: { services: [ { id: "web" } ] }, pagination: { hasNextPage: true, cursor: "c2", count: 1 } }))
      Http.expects(:request).with { |uri, _| URI.decode_www_form(uri.query).to_h == { "per_page" => "100", "cursor" => "c2" } }
          .returns(response(200, { data: { services: [ { id: "api" } ] }, pagination: { hasNextPage: false, count: 1 } }))

      listed = @api.services("firefight")

      assert_equal %w[web api], listed.items.map { |service| service["id"] }
      assert_not listed.incomplete?

      Http.unstub(:request)
      Http.stubs(:request).returns(response(200, { data: { jobs: [ { id: "nightly" } ] }, pagination: { hasNextPage: true, cursor: "next", count: 1 } }))
      cut = @api.jobs("firefight")
      assert cut.incomplete?
      assert_equal NorthflankApi::MAX_PAGES, cut.items.size
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

    test "query options are encoded after the project path, so a value never reaches the path" do
      Http.expects(:request).with do |uri, request, **|
        uri.path == "/v1/projects/firefight/services" && request.is_a?(Net::HTTP::Get) &&
          uri.query == "per_page=100&cursor=a%2F..%2Fb%3Fc%3Dd%26e" && URI.decode_www_form(uri.query).to_h == { "per_page" => "100", "cursor" => "a/../b?c=d&e" }
      end.returns(response(200, { data: {} }))

      @api.request("GET", "firefight", "services", nil, { "per_page" => "100", "cursor" => "a/../b?c=d&e" })
    end

    test "a change Northflank accepted stays accepted when what came back is not JSON" do
      Http.stubs(:request).returns(stub(code: "200", body: "OK"))

      assert_equal({}, @api.request("POST", "firefight", "services/web/restart"))
    end

    test "a notification integration is listed, made for the project and deleted at the paths the client gives, and a refusal is told apart" do
      Http.expects(:request).with { |uri, request, **| uri.path == "/v1/integrations/notifications" && request.is_a?(Net::HTTP::Get) }
          .returns(response(200, { data: { notificationIntegrations: [ { id: "theirs", webhook: "https://example.com" } ] }, pagination: { hasNextPage: false } }))
      assert_equal [ "theirs" ], @api.notifications.items.map { |integration| integration["id"] }

      Http.expects(:request).with do |uri, request, **|
        uri.path == "/v1/integrations/notifications" && request.is_a?(Net::HTTP::Post) &&
          JSON.parse(request.body) == { "name" => "Firefight live updates", "type" => "RAW_WEBHOOK", "webhook" => "https://ff.example/hook", "secret" => "s3cret",
                                        "restricted" => true, "projects" => [ "firefight" ], "events" => { "trigger:build:start" => true } }
      end.returns(response(200, { data: { id: "firefight-live-updates" } }))
      assert_equal "firefight-live-updates", @api.create_notification(name: "Firefight live updates", url: "https://ff.example/hook", secret: "s3cret",
                                                                      events: [ "trigger:build:start" ], projects: [ "firefight" ])["id"]

      Http.expects(:request).with { |uri, request, **| uri.path == "/v1/integrations/notifications/firefight-live-updates" && request.is_a?(Net::HTTP::Delete) }
          .returns(response(200, { data: {} }))
      @api.delete_notification("firefight-live-updates")

      Http.stubs(:request).returns(response(403, { error: { message: "Missing permission: Notifications Create" } }))
      assert_raises(NorthflankApi::Refused) { @api.notifications }
      Http.stubs(:request).returns(response(404, { error: { message: "Job not found" } }))
      assert_raises(NorthflankApi::NotFound) { @api.job("firefight", "nightly") }
    end

    private

    def response(code, body)
      stub(code: code.to_s, body: body.to_json)
    end
  end
end
