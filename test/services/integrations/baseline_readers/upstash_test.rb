require "test_helper"

module Integrations
  module BaselineReaders
    class UpstashTest < ActiveSupport::TestCase
      WEEK = { "type" => "object", "properties" => { "database_id" => { "type" => "string" }, "period" => { "type" => "string", "enum" => %w[1h 7d] } } }.freeze

      setup do
        @resource = ResourceMap::Resource.new(provider: "upstash", account: "upstash", kind: ResourceMap::KIND_DATABASE, external_id: "96ad0856", name: "sessions")
        @window = Time.utc(2026, 9, 24)..Time.utc(2026, 10, 1)
      end

      test "a week of stats is asked when the tool offers 7d, and read into what normal looks like" do
        asked = nil
        stats = { "throughput" => [ { "x" => "2026-09-30 10:00:00 +0000 UTC", "y" => 40 }, { "x" => "2026-09-01 10:00:00 +0000 UTC", "y" => 900 } ],
                  "connection_count" => [ { "x" => "2026-09-30 10:00:00 +0000 UTC", "y" => 7 } ] }
        found = Upstash.new(nil, { "redis_get_stats" => tool(WEEK) }) do |name, arguments|
          asked = [ name, arguments ]
          { "content" => [ { "type" => "text", "text" => stats.to_json } ] }
        end.baselines([ @resource ], @window)

        assert_equal [ "redis_get_stats", { "database_id" => "96ad0856", "period" => "7d" } ], asked
        assert_equal({ "requests" => [ 40.0 ], "tcp_connections" => [ 7.0 ] }, found.to_h { |reading| [ reading.metric, reading.points.map(&:last) ] })
      end

      test "a tool that offers no week, or one switched off, is not asked, rather than a shorter window being passed off as normal" do
        reader = Upstash.new(nil, { "redis_get_stats" => tool(WEEK.deep_merge("properties" => { "period" => { "enum" => %w[1h 1d] } })) }) { |*| flunk("asked") }
        assert_empty reader.baselines([ @resource ], @window)
        assert_nil Upstash.new(nil, {}) { |*| flunk("asked") }.baselines([ @resource ], @window)
      end

      private

      def tool(schema) = Integration::Tool.new(name: "redis_get_stats", params_schema: schema)
    end
  end
end
