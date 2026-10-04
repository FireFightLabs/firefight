require "test_helper"

module Integrations
  class TriggerDevApiTest < ActiveSupport::TestCase
    setup do
      @api = TriggerDevApi.new("tr_prod_sk_abc")
    end

    test "runs are filtered in the deepObject style, a list comma separated, and later pages follow the cursor" do
      Http.expects(:request).with do |uri, request, **|
        query = URI.decode_www_form(uri.query).to_h
        uri.path == "/api/v1/runs" && request["Authorization"] == "Bearer tr_prod_sk_abc" && query["filter[status]"] == "FAILED,CRASHED" &&
          query["filter[taskIdentifier]"] == "send-email" && query["filter[createdAt][from]"] == "2026-10-01T00:00:00Z" &&
          query["page[size]"] == "12" && !query.key?("page[after]")
      end.returns(response(200, { data: Array.new(10) { |index| { id: "run_#{index}" } }, pagination: { next: "run_9" } }))
      Http.expects(:request).with { |uri, _request, **| URI.decode_www_form(uri.query).to_h["page[after]"] == "run_9" }
          .returns(response(200, { data: [ { id: "run_10" }, { id: "run_11" }, { id: "run_12" } ], pagination: {} }))

      runs = @api.runs(filter: { "taskIdentifier" => [ "send-email" ], "status" => %w[FAILED CRASHED], "createdAt" => { "from" => "2026-10-01T00:00:00Z", "to" => nil } },
                       limit: 12)

      assert_equal 12, runs.size
      assert_equal "run_11", runs.last["id"]
    end

    test "a deployment list asks for at least the five a page Trigger.dev allows" do
      Http.expects(:request).with { |uri, _request, **| URI.decode_www_form(uri.query).to_h == { "status" => "DEPLOYED", "page[size]" => "5" } }
          .returns(response(200, { data: [ { id: "deployment_1", version: "20261001.1" } ] }))

      assert_equal [ "deployment_1" ], @api.deployments(status: "DEPLOYED", limit: 1).map { |deployment| deployment["id"] }
    end

    test "a query is sent with its range beside it, and its rows come back" do
      Http.expects(:request).with do |uri, request, **|
        body = JSON.parse(request.body)
        uri.path == "/api/v1/query" && request.is_a?(Net::HTTP::Post) && body["query"] == "SELECT count() FROM runs" &&
          body["from"] == "2026-10-01T00:00:00Z" && body["to"] == "2026-10-02T00:00:00Z" && body["scope"] == "environment"
      end.returns(response(200, { format: "json", results: [ { "count()" => 4 } ] }))

      rows = @api.query("SELECT count() FROM runs", from: Time.utc(2026, 10, 1), to: Time.utc(2026, 10, 2))

      assert_equal [ { "count()" => 4 } ], rows
    end

    test "queues are read a numbered page at a time until the last" do
      Http.expects(:request).with { |uri, _request, **| URI.decode_www_form(uri.query).to_h["page"] == "1" }
          .returns(response(200, { data: [ { name: "a" } ], pagination: { currentPage: 1, totalPages: 2 } }))
      Http.expects(:request).with { |uri, _request, **| URI.decode_www_form(uri.query).to_h["page"] == "2" }
          .returns(response(200, { data: [ { name: "b" } ], pagination: { currentPage: 2, totalPages: 2 } }))

      read = @api.queues

      assert_equal %w[a b], read.items.map { |queue| queue["name"] }
      assert_not read.incomplete?
    end

    test "Trigger.dev's refusal is raised with its own reason, and too many requests is its own error" do
      Http.stubs(:request).returns(response(400, { error: "Deployment is not deployed" }))
      error = assert_raises(TriggerDevApi::Error) { @api.promote("20261001.1") }
      assert_equal "Trigger.dev answered 400: Deployment is not deployed", error.message

      Http.stubs(:request).returns(response(429, {}))
      limited = assert_raises(TriggerDevApi::Error) { @api.run("run_1") }
      assert_kind_of Integrations::RateLimited, limited
    end

    test "a change that went through stays done whatever came back with it" do
      Http.stubs(:request).returns(stub(code: "200", body: "ok"))

      assert_equal({}, @api.promote("20261001.1"))
    end

    private

    def response(code, body)
      stub(code: code.to_s, body: body.to_json)
    end
  end
end
