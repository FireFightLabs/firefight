require "test_helper"

module Integrations
  module MapReaders
    class UpstashTest < ActiveSupport::TestCase
      DATABASE = { "database_id" => "96ad0856", "database_name" => "sessions", "state" => "active", "primary_region" => "eu-central-1",
                   "type" => "payg", "eviction" => true }.freeze

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
        assert_equal [ ResourceMap::KIND_QUEUE, "qstash-q-1", "QStash eu", "https://console.upstash.com/qstash" ], [ queue.kind, queue.external_id, queue.name, queue.url ]
        assert_equal "eu", queue.details["region"]
        assert_equal [ [ "qstash_list_users", { "region" => "us" } ], [ "qstash_list_users", { "region" => "eu" } ] ], asked.drop(1)
        assert asked.none? { |_tool, arguments| arguments.key?("include_credentials") }
        assert_empty snapshot.gaps
      end

      test "two Upstash accounts each keep their own QStash on the map, keyed by the account's QStash user" do
        keys = %w[first second].map do |name|
          integration = workspaces(:slack_workspace_one).integrations.create!(kind: Integration::KIND_MCP, provider: "upstash", name: "Upstash #{name}",
                                                                              settings: { "server_url" => "https://mcp.upstash.com/mcp" })
          settings = ConnectionSettings.of(integration.integration_environments.create!)
          Upstash.new(settings) do |tool, arguments|
            tool == Upstash::LIST_QSTASH && arguments["region"] == "eu" ? result([ { "id" => "user-#{name}", "state" => "active" } ]) : result([])
          end.map.resources.map(&:key)
        end

        assert_equal [ [ [ "upstash", "upstash", ResourceMap::KIND_QUEUE, "qstash-user-first" ] ], [ [ "upstash", "upstash", ResourceMap::KIND_QUEUE, "qstash-user-second" ] ] ], keys
      end

      test "a QStash listed without its user's id is keyed by its region and the connection, so two accounts still differ" do
        integration = workspaces(:slack_workspace_one).integrations.create!(kind: Integration::KIND_MCP, provider: "upstash", name: "Upstash",
                                                                            settings: { "server_url" => "https://mcp.upstash.com/mcp" })
        settings = ConnectionSettings.of(integration.integration_environments.create!)
        snapshot = Upstash.new(settings) do |tool, arguments|
          tool == Upstash::LIST_QSTASH && arguments["region"] == "us" ? result([ { "state" => "active" } ]) : result([])
        end.map

        assert_equal [ "qstash-us-#{integration.id}" ], snapshot.resources.map(&:external_id)
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
