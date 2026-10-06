require "test_helper"

module Integrations
  module MapReaders
    class UpstashTest < ActiveSupport::TestCase
      DATABASE = { "database_id" => "96ad0856", "database_name" => "sessions", "state" => "active", "primary_region" => "eu-central-1",
                   "type" => "payg", "eviction" => true, "endpoint" => "clean-crab-89681", "port" => 6379 }.freeze
      Tool = Struct.new(:params_schema)

      test "Redis databases and the QStash of each region go on the map, with the console page they are on" do
        integration = workspaces(:slack_workspace_one).integrations.create!(kind: Integration::KIND_MCP, provider: "upstash", name: "Upstash",
                                                                            settings: { "server_url" => "https://mcp.upstash.com/mcp" })
        settings = ConnectionSettings.of(integration.integration_environments.create!)
        asked = []
        snapshot = Upstash.new(settings) do |tool, arguments|
          asked << [ tool, arguments ]
          if tool == Upstash::LIST_DATABASES then result([ DATABASE ])
          elsif arguments["region"] == "eu" then result([ { "id" => "q-1", "state" => "active", "max_retries" => 3 } ])
          else result([])
          end
        end.map

        database, queue = snapshot.resources
        assert_equal [ "upstash", "upstash", ResourceMap::KIND_DATABASE, "96ad0856" ], database.key
        assert_equal [ "sessions", "active", "https://console.upstash.com/redis" ], [ database.name, database.status, database.url ]
        assert_equal({ "engine" => "redis", "region" => "eu-central-1", "plan" => "payg", "eviction" => true }, database.details)
        assert_equal [ ResourceMap::KIND_QUEUE, "qstash-eu", "QStash eu", "https://console.upstash.com/qstash" ], [ queue.kind, queue.external_id, queue.name, queue.url ]
        assert_equal "eu", queue.details["region"]
        assert_equal [ [ "qstash_list_users", { "region" => "us" } ], [ "qstash_list_users", { "region" => "eu" } ] ], asked.drop(1)
        assert asked.none? { |_tool, arguments| arguments.key?("include_credentials") }
        assert_empty snapshot.gaps
        assert_equal [ 6379, 443 ], snapshot.endpoints.map(&:port)
        assert_equal ResourceMap::Fingerprint.of("clean-crab-89681.upstash.io", 6379, settings.workspace), snapshot.endpoints.first.fingerprint
        assert snapshot.endpoints.all? { |endpoint| endpoint.resource == database.key }
      end

      test "a database listed without its address is described without credentials when that tool is on, and is a settings gap when it is off" do
        integration = workspaces(:slack_workspace_one).integrations.create!(kind: Integration::KIND_MCP, provider: "upstash", name: "Upstash",
                                                                            settings: { "server_url" => "https://mcp.upstash.com/mcp" })
        settings = ConnectionSettings.of(integration.integration_environments.create!)
        listed = DATABASE.except("endpoint", "port")
        asked = []
        described = Upstash.new(settings, { Upstash::GET_DATABASE => Tool.new({}) }) do |tool, arguments|
          asked << [ tool, arguments ]
          case tool
          when Upstash::LIST_DATABASES then result([ listed ])
          when Upstash::GET_DATABASE then result(listed.merge("endpoint" => "clean-crab-89681.upstash.io", "port" => 6380))
          else result([])
          end
        end.map

        assert_equal [ 6380, 443 ], described.endpoints.map(&:port)
        assert_equal [ { "database_id" => "96ad0856" } ], asked.select { |tool, _| tool == Upstash::GET_DATABASE }.map(&:last)
        assert_empty described.gaps

        off = Upstash.new(settings) { |tool, _| tool == Upstash::LIST_DATABASES ? result([ listed ]) : result([]) }.map
        assert_empty off.endpoints
        assert_equal [ true ], off.gaps.map(&:settings)
        assert off.complete?
        assert_not off.settings_complete?
      end

      test "a switched off tool or a refusal is a gap, and that kind is not taken as gone" do
        snapshot = Upstash.new do |tool, _arguments|
          tool == Upstash::LIST_DATABASES ? nil : { "isError" => true, "content" => [ { "type" => "text", "text" => "read-only key" } ] }
        end.map

        assert_includes snapshot.gaps.map(&:text), "redis_list_databases is switched off for Upstash, so the Redis databases are not on the map."
        assert_includes snapshot.gaps.map(&:text), "Upstash refused to list the QStash of the us region: read-only key."
        assert_equal [ ResourceMap::KIND_DATABASE, ResourceMap::KIND_QUEUE ], snapshot.unread_kinds
      end

      private

      def result(body) = { "content" => [ { "type" => "text", "text" => body.to_json } ] }
    end
  end
end
