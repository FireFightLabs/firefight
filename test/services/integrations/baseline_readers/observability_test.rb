require "test_helper"

module Integrations
  module BaselineReaders
    class ObservabilityTest < ActiveSupport::TestCase
      setup do
        @workspace = workspaces(:slack_workspace_one)
        @web = ResourceMap::Resource.create!(workspace: @workspace, provider: "northflank", account: "team/prod", kind: ResourceMap::KIND_SERVICE, external_id: "web-id",
                                             name: "web", first_seen_at: Time.current, last_seen_at: Time.current)
        @window = Time.utc(2026, 9, 27)..Time.utc(2026, 10, 4)
      end

      test "Logfire reads a week of each metric per service in hourly buckets" do
        asked = []
        rows = [ { "bucket" => "2026-10-03T10:00:00Z", "service_name" => "web", "metric" => "requests", "value" => 12.5 },
                 { "bucket" => "2026-10-03T11:00:00Z", "service_name" => "web", "metric" => "requests", "value" => 14 },
                 { "bucket" => "2026-10-03T10:00:00Z", "service_name" => "other", "metric" => "cpu", "value" => 3 } ]
        found = Logfire.new(nil) { |name, arguments, _reads| asked << [ name, arguments ] && answer(rows) }.baselines([ @web ], @window)

        assert_equal "query_run", asked.sole.first
        assert_equal [ "2026-09-27T00:00:00Z", "2026-10-04T00:00:00Z" ], asked.sole.last.values_at("min_timestamp", "max_timestamp")
        assert_match "time_bucket(interval '3600 seconds', start_timestamp)", asked.sole.last["query"]
        reading = found.sole
        assert_equal [ @web.key, "requests", "Requests", "per minute" ], [ reading.key, reading.metric, reading.label, reading.unit ]
        assert_equal [ 12.5, 14.0 ], reading.points.map(&:last)
      end

      test "SigNoz reads requests and errors per minute for each service in one call" do
        series = [ { "labels" => [ { "key" => { "name" => "service.name" }, "value" => "web" }, { "key" => { "name" => "has_error" }, "value" => "false" } ],
                     "values" => [ { "timestamp" => 1_759_485_600_000, "value" => 540 } ] },
                   { "labels" => [ { "key" => { "name" => "service.name" }, "value" => "web" }, { "key" => { "name" => "has_error" }, "value" => "true" } ],
                     "values" => [ { "timestamp" => 1_759_485_600_000, "value" => 60 } ] } ]
        asked = nil
        found = Signoz.new(nil) { |_name, arguments, _reads| (asked = arguments) && answer({ "data" => { "data" => { "results" => [ { "aggregations" => [ { "series" => series } ] } ] } } }) }
                      .baselines([ @web ], @window)

        assert_equal "service.name IN ('web')", asked["filter"]
        assert_equal({ "requests" => [ 10.0 ], "errors" => [ 1.0 ] }, found.to_h { |reading| [ reading.metric, reading.points.map(&:last) ] })
      end

      test "a reader whose tool is off reads nothing, and one refused every time says why" do
        assert_nil Logfire.new(nil) { nil }.baselines([ @web ], @window)
        error = assert_raises(Integrations::Error) { Signoz.new(nil) { { "isError" => true, "content" => [ { "type" => "text", "text" => "rate limited" } ] } }.baselines([ @web ], @window) }
        assert_equal "SigNoz could not read normal: rate limited.", error.message
      end

      private

      def answer(body) = { "content" => [ { "type" => "text", "text" => body.to_json } ] }
    end
  end
end
