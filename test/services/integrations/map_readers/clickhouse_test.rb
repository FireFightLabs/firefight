require "test_helper"

module Integrations
  module MapReaders
    class ClickhouseTest < ActiveSupport::TestCase
      ORGANIZATION = { "id" => "6b3a2f1e-0000-4000-8000-000000000001", "name" => "Acme" }.freeze
      SERVICE = { "id" => "svc-1", "name" => "analytics", "state" => "running", "provider" => "aws", "region" => "eu-central-1",
                  "clickhouseVersion" => "25.8", "numReplicas" => 3, "idleScaling" => true, "isReadonly" => false }.freeze

      test "every organization's services go on the map as databases, with their state and setup" do
        snapshot = Clickhouse.new do |tool, arguments|
          tool == Clickhouse::LIST_ORGANIZATIONS ? result("status" => 200, "result" => [ ORGANIZATION ]) : result([ SERVICE ]).tap { assert_equal ORGANIZATION["id"], arguments["organizationId"] }
        end.map

        service = snapshot.resources.sole
        assert_equal [ "clickhouse", ORGANIZATION["id"], ResourceMap::KIND_DATABASE, "svc-1" ], service.key
        assert_equal [ "analytics", "running" ], [ service.name, service.status ]
        assert_equal({ "organization" => "Acme", "cloud" => "aws", "region" => "eu-central-1", "version" => "25.8", "replicas" => 3,
                       "idle_scaling" => true, "read_only" => false }, service.details)
        assert_empty snapshot.gaps
        assert_empty snapshot.unread_kinds
      end

      test "a tool switched off, a refusal or an answer it cannot read is a gap, and nothing is taken as gone" do
        off = Clickhouse.new { |tool, _arguments| tool == Clickhouse::LIST_SERVICES ? nil : result([ ORGANIZATION ]) }.map
        assert_equal [ "get_services_list is switched off for ClickHouse, so the services in Acme are not on the map." ], off.gaps.map(&:text)
        assert_equal [ ResourceMap::KIND_DATABASE ], off.unread_kinds

        refused = Clickhouse.new { |_tool, _arguments| { "isError" => true, "content" => [ { "type" => "text", "text" => "Unauthorized" } ] } }.map
        assert_equal [ "ClickHouse refused to list the organizations: Unauthorized." ], refused.gaps.map(&:text)
        assert_equal [ ResourceMap::KIND_DATABASE ], refused.unread_kinds

        odd = Clickhouse.new { |_tool, _arguments| { "content" => [ { "type" => "text", "text" => "{\"ok\":true}" } ] } }.map
        assert_match "in a shape Firefight does not read", odd.gaps.sole.text
        assert_equal [ ResourceMap::KIND_DATABASE ], odd.unread_kinds
      end

      test "a service is reached at the endpoints its object lists, or those get_service_details gives, or it is a settings gap" do
        workspace = workspaces(:slack_workspace_one)
        settings = ConnectionSettings.of(workspace.integrations.build(kind: Integration::KIND_MCP, provider: Clickhouse::PROVIDER).integration_environments.build)
        endpoints = [ { "protocol" => "https", "host" => "abc123.eu-central-1.aws.clickhouse.cloud", "port" => 8443 },
                      { "protocol" => "nativesecure", "host" => "abc123.eu-central-1.aws.clickhouse.cloud", "port" => 9440 } ]
        listed = Clickhouse.new(settings) do |tool, _|
          tool == Clickhouse::LIST_ORGANIZATIONS ? result([ ORGANIZATION ]) : result([ SERVICE.merge("endpoints" => endpoints) ])
        end.map
        assert_equal [ 8443, 9440 ], listed.endpoints.map(&:port)
        assert_equal ResourceMap::Fingerprint.of("abc123.eu-central-1.aws.clickhouse.cloud", 8443, workspace), listed.endpoints.first.fingerprint

        tool = Struct.new(:params_schema).new({})
        asked = []
        described = Clickhouse.new(settings, { Clickhouse::DETAILS => tool }) do |name, arguments|
          asked << [ name, arguments ]
          case name
          when Clickhouse::LIST_ORGANIZATIONS then result([ ORGANIZATION ])
          when Clickhouse::DETAILS then result("result" => SERVICE.merge("endpoints" => endpoints))
          else result([ SERVICE ])
          end
        end.map
        assert_equal [ 8443, 9440 ], described.endpoints.map(&:port)
        assert_equal({ "organizationId" => ORGANIZATION["id"], "serviceId" => "svc-1" }, asked.assoc(Clickhouse::DETAILS).last)

        off = Clickhouse.new(settings) { |name, _| name == Clickhouse::LIST_ORGANIZATIONS ? result([ ORGANIZATION ]) : result([ SERVICE ]) }.map
        assert_equal [ true ], off.gaps.map(&:settings)
        assert_match "get_service_details is switched off", off.gaps.sole.text
      end

      private

      def result(body) = { "content" => [ { "type" => "text", "text" => body.to_json } ] }
    end
  end
end
