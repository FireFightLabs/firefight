require "test_helper"

module Integrations
  class RailwayApiTest < ActiveSupport::TestCase
    setup do
      @api = RailwayApi.new("rw-token")
    end

    test "a query goes to the GraphQL endpoint with the token and its variables, and its data comes back" do
      Http.expects(:request).with do |uri, request, **|
        body = JSON.parse(request.body)
        uri.to_s == RailwayApi::ENDPOINT && request["Authorization"] == "Bearer rw-token" &&
          body["query"].include?("project(id: $id)") && body["variables"] == { "id" => "prj-1" }
      end.returns(response(200, { data: { project: { id: "prj-1", name: "shop" } } }))

      assert_equal({ "id" => "prj-1", "name" => "shop" }, @api.project("prj-1"))
    end

    test "service instances are read page by page until Railway says there are no more" do
      page = ->(id, more) { { data: { environment: { serviceInstances: { edges: [ { node: { serviceId: id } } ], pageInfo: { hasNextPage: more, endCursor: "c-#{id}" } } } } } }
      Http.expects(:request).with { |_, request, **| JSON.parse(request.body)["variables"]["after"].nil? }.returns(response(200, page.("a", true)))
      Http.expects(:request).with { |_, request, **| JSON.parse(request.body)["variables"]["after"] == "c-a" }.returns(response(200, page.("b", false)))

      read = @api.service_instances("prj-1", "env-1")
      assert_equal %w[a b], read.items.map { |instance| instance["serviceId"] }
      assert_not read.incomplete?
    end

    test "a refusal Railway answers with 200 and an errors list is raised in its own words" do
      Http.stubs(:request).returns(response(200, { errors: [ { message: "Not Authorized", extensions: { code: "INTERNAL_SERVER_ERROR" } } ] }))

      error = assert_raises(RailwayApi::Error) { @api.project("prj-1") }

      assert_equal "Railway refused this: Not Authorized", error.message
    end

    test "a change selects nothing on the Boolean Railway answers, and being asked to slow down is its own error" do
      Http.expects(:request).with { |_, request, **| JSON.parse(request.body)["query"].include?("{ deploymentRollback(id: $id) }") }
          .returns(response(200, { data: { deploymentRollback: true } }))
      assert @api.rollback("dep-1")

      Http.stubs(:request).returns(response(429, { errors: [ { message: "Rate limit exceeded" } ] }))
      assert_raises(Integrations::RateLimited) { @api.restart("dep-1") }
    end

    test "a project's webhook is a notification rule with a webhook channel carrying Firefight's header, outside preview environments" do
      Http.expects(:request).with do |_, request, **|
        body = JSON.parse(request.body)
        input = body.dig("variables", "input")
        body["query"].include?("notificationRuleCreate(input: $input)") && input["workspaceId"] == "ws-1" && input["projectId"] == "prj-1" &&
          input["eventTypes"] == %w[Deployment.failed] && input["ephemeralEnvironments"] == false &&
          input["channelConfigs"] == [ { "type" => "webhook", "url" => "https://ff.example/hook", "headers" => { "X-Secret" => "s" } } ]
      end.returns(response(200, { data: { notificationRuleCreate: { id: "rule-1" } } }))

      assert_equal({ "id" => "rule-1" }, @api.create_webhook("ws-1", "prj-1", url: "https://ff.example/hook", events: %w[Deployment.failed], headers: { "X-Secret" => "s" }))

      Http.expects(:request).with { |_, request, **| JSON.parse(request.body).dig("variables", "id") == "rule-1" && request.body.include?("notificationRuleDelete") }
          .returns(response(200, { data: { notificationRuleDelete: true } }))
      assert @api.delete_webhook("rule-1")
    end

    test "Railway saying something is not there is NotFound, and a refusal of the request as it stands is Refused" do
      Http.stubs(:request).returns(response(200, { errors: [ { message: "ServiceInstance not found" } ] }))
      assert_raises(RailwayApi::NotFound) { @api.service_instance("env-1", "svc-1") }

      Http.stubs(:request).returns(response(200, { errors: [ { message: "Not Authorized" } ] }))
      assert_raises(RailwayApi::Refused) { @api.create_webhook("ws-1", "prj-1", url: "https://ff.example/hook", events: [], headers: {}) }

      Http.stubs(:request).returns(response(200, { errors: [ { message: "Problem processing request" } ] }))
      error = assert_raises(RailwayApi::Error) { @api.notification_rules("ws-1", "prj-1") }
      assert_equal RailwayApi::Error, error.class
    end

    private

    def response(code, body)
      stub(code: code.to_s, body: body.to_json)
    end
  end
end
