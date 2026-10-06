require "test_helper"

module Integrations
  class RenderApiTest < ActiveSupport::TestCase
    setup do
      @api = RenderApi.new("rnd_key")
    end

    test "a list filter is sent once per value with the key, and a log page comes back as Render answered it" do
      Http.expects(:request).with do |uri, request, **|
        query = URI.decode_www_form(uri.query)
        uri.path == "/v1/logs" && request["Authorization"] == "Bearer rnd_key" && request["Accept"] == "application/json" &&
          query.count { |name, _| name == "text" } == 2 && query.include?([ "ownerId", "tea-1" ]) && query.none? { |name, _| name.include?("[") }
      end.returns(response(200, { hasMore: false, logs: [] }))

      assert_equal({ "hasMore" => false, "logs" => [] }, @api.logs("ownerId" => "tea-1", "resource" => "srv-1", "text" => [ "timeout", "/5../" ]))
    end

    test "a list is read page by page from the last cursor, and only the rows come back" do
      first = Array.new(RenderApi::PAGE_SIZE) { |index| { cursor: "c#{index}", service: { id: "srv-#{index}" } } }
      Http.expects(:request).with { |uri, *| !uri.query.include?("cursor") }.returns(response(200, first))
      Http.expects(:request).with { |uri, *| URI.decode_www_form(uri.query).include?([ "cursor", "c#{RenderApi::PAGE_SIZE - 1}" ]) }
          .returns(response(200, [ { cursor: "last", service: { id: "srv-last" } } ]))

      services = @api.services("tea-1")

      assert_equal RenderApi::PAGE_SIZE + 1, services.items.size
      assert_equal "srv-last", services.items.last["id"]
      assert_not services.incomplete?
    end

    test "a list still going at the last page it reads says it was not read to its end" do
      full = Array.new(RenderApi::PAGE_SIZE) { |index| { cursor: "c#{index}", postgres: { id: "dpg-#{index}" } } }
      Http.stubs(:request).returns(response(200, full))

      databases = @api.postgres_databases("tea-1")

      assert databases.incomplete?
      assert_equal RenderApi::PAGE_SIZE * RenderApi::MAX_PAGES, databases.items.size
    end

    test "a change is sent as JSON, and Render's refusal comes back in its own words" do
      Http.expects(:request).with do |uri, request, **|
        uri.path == "/v1/services/srv-1/scale" && request.is_a?(Net::HTTP::Post) && JSON.parse(request.body) == { "numInstances" => 3 }
      end.returns(stub(code: "202", body: ""))
      assert_equal({}, @api.scale("srv-1", 3))

      Http.stubs(:request).returns(response(403, { id: "x", message: "You do not have permissions for the requested resource." }))
      error = assert_raises(RenderApi::Error) { @api.restart_service("srv-1") }
      assert_equal "Render answered 403: You do not have permissions for the requested resource.", error.message
    end

    test "a webhook is made for the workspace with the events named, switched on again, and deleted, at the paths the spec gives" do
      Http.expects(:request).with do |uri, request, **|
        uri.path == "/v1/webhooks" && request.is_a?(Net::HTTP::Post) &&
          JSON.parse(request.body) == { "ownerId" => "tea-1", "name" => "Firefight", "url" => "https://ff.example/hook", "enabled" => true, "eventFilter" => [ "deploy_ended" ] }
      end.returns(response(201, { id: "whk-1", secret: "whsec_abc" }))
      assert_equal "whsec_abc", @api.create_webhook("tea-1", name: "Firefight", url: "https://ff.example/hook", events: [ "deploy_ended" ])["secret"]

      Http.expects(:request).with { |uri, request, **| uri.path == "/v1/webhooks/whk-1" && request.is_a?(Net::HTTP::Patch) && JSON.parse(request.body) == { "enabled" => true } }
          .returns(response(200, { id: "whk-1", enabled: true }))
      assert @api.enable_webhook("whk-1")["enabled"]

      Http.expects(:request).with { |uri, request, **| uri.path == "/v1/webhooks/whk-1" && request.is_a?(Net::HTTP::Delete) }.returns(stub(code: "204", body: ""))
      assert_equal({}, @api.delete_webhook("whk-1"))

      Http.expects(:request).with { |uri, *| uri.path == "/v1/webhooks" && URI.decode_www_form(uri.query).include?([ "ownerId", "tea-1" ]) }
          .returns(response(200, [ { cursor: "c1", webhook: { id: "whk-1", url: "https://ff.example/hook" } } ]))
      assert_equal [ "whk-1" ], @api.webhooks("tea-1").items.map { |webhook| webhook["id"] }
    end

    test "not found and a request turned down as it stands are told apart from other refusals" do
      Http.stubs(:request).returns(response(404, { message: "not found" }))
      assert_raises(RenderApi::NotFound) { @api.service("srv-1") }

      Http.stubs(:request).returns(response(400, { message: "webhooks are not available on your plan" }))
      assert_raises(RenderApi::Refused) { @api.create_webhook("tea-1", name: "Firefight", url: "https://ff.example/hook", events: []) }

      Http.stubs(:request).returns(response(401, { message: "unauthorized" }))
      error = assert_raises(RenderApi::Error) { @api.owner("tea-1") }
      assert_not error.is_a?(RenderApi::Refused)
    end

    test "being asked to slow down is its own error" do
      Http.stubs(:request).returns(response(429, { message: "rate limit exceeded" }))

      assert_raises(Integrations::RateLimited) { @api.owner("tea-1") }
    end

    private

    def response(code, body)
      stub(code: code.to_s, body: body.to_json)
    end
  end
end
