require "test_helper"

module Integrations
  # A provider's health probe and baseline reader, named by its definition and run through its remote server's
  # switched on tools, each call recorded.
  class RemoteReaderTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    class Probe < RemoteReader
      def check!
        answer = call("list_sources", { "limit" => 10 })
        return if answer.nil?
        raise Refused, "Acme refused list_sources: #{answer.dig('content', 0, 'text')}" if answer["isError"]

        { "sources" => JSON.parse(answer.dig("content", 0, "text")), "region" => settings.region&.key }
      end
    end

    class Normal < RemoteReader
      def baselines(resources, window)
        return unless on?("query")

        answer = JSON.parse(call("query", { "from" => window.begin.iso8601 }, "normal for #{resources.size} services").dig("content", 0, "text"))
        resources.map { |resource| ResourceMap::Baseline::Found.new(key: resource.key, metric: "cpu", label: "CPU", unit: "%", points: [ [ window.end, answer["cpu"] ] ]) }
      end
    end

    setup do
      @workspace = workspaces(:slack_workspace_one)
      @datadog = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "datadog", name: "Datadog",
                                                 settings: { "server_url" => "https://mcp.datadoghq.eu/v1/mcp", "region" => "eu1" })
      @row = @datadog.integration_environments.create!
      @listing = @datadog.tools.create!(name: "list_sources", read_only: true, enabled: true, spec: { "tool_name" => "list_sources" })
      definition = Provider.new(key: "datadog", adapter: "Integrations::Capabilities::Datadog", health_probe: "Integrations::RemoteReaderTest::Probe",
                                baseline_reader: "Integrations::RemoteReaderTest::Normal", redacted_fields: [ "token" ])
      Provider.stubs(:for).returns(definition)
      McpClient.any_instance.stubs(:ping).returns(true)
    end

    test "a probe reads through a switched on tool, recorded under the health check, and what it learned is kept on the row" do
      McpClient.any_instance.expects(:call_tool).with(name: "list_sources", arguments: { "limit" => 10 })
               .returns({ "content" => [ { "type" => "text", "text" => '["logs"]' } ] })

      assert HealthCheckService.check!(@row)

      assert_equal({ "sources" => [ "logs" ], "region" => "eu1" }, ConnectionSettings.of(@row.reload).learned)
      call = Ability::Invocation.find_by!(action_key: @listing.action_key)
      assert_equal [ AbilityGateway::SOURCE_HEALTH_CHECK, SystemAgent.health_check.id ], [ call.source, call.principal_id ]
    end

    test "a probe's refusal marks the connection failing with the provider's words, and a switched off tool is never called" do
      McpClient.any_instance.stubs(:call_tool).returns({ "isError" => true, "content" => [ { "type" => "text", "text" => "401 bad key" } ] })
      assert_not HealthCheckService.check!(@row)
      assert_equal [ IntegrationEnvironment::HEALTH_FAILING, "Acme refused list_sources: 401 bad key" ], [ @row.reload.health_status, @row.health_error ]

      @listing.update!(enabled: false)
      McpClient.any_instance.expects(:call_tool).never
      assert HealthCheckService.check!(@row)
    end

    test "switching a tool on or off checks again a connection whose probe reads through its tools, and no other" do
      assert_enqueued_with(job: HealthCheckJob, args: [ @row ]) { ConnectionRefresh.tools_changed(@datadog) }

      Provider.stubs(:for).returns(Provider.new(key: "datadog"))
      assert_no_enqueued_jobs(only: HealthCheckJob) { ConnectionRefresh.tools_changed(@datadog) }
    end

    test "a baseline reader reads through the connection's tools, each call recorded under the map sweep with what it read" do
      @datadog.tools.create!(name: "query", read_only: true, enabled: true, spec: { "tool_name" => "query" })
      McpClient.any_instance.expects(:call_tool).with { |name:, arguments:| name == "query" && arguments.key?("from") }
               .returns({ "content" => [ { "type" => "text", "text" => '{"cpu": 41.5}' } ] })
      resource = ResourceMap::Resource.new(workspace: @workspace, provider: "northflank", account: "acme", kind: ResourceMap::KIND_SERVICE, external_id: "web", name: "web")

      found = McpExecutor.baselines_of(@row, [ resource ], (1.week.ago)..Time.current)

      assert_equal [ 41.5 ], found.sole.points.map(&:last)
      call = Ability::Invocation.find_by!(action_key: "datadog.query")
      assert_equal [ AbilityGateway::SOURCE_MAP_SWEEP, "normal for 1 services" ], [ call.source, call.params["reads"] ]
    end

    test "fields a provider's definition names as credentials never reach whoever reads the answer" do
      McpClient.any_instance.stubs(:call_tool).returns(
        { "content" => [ { "type" => "text", "text" => '{"project":{"name":"web","token":"hbp_secret"}}' }, { "type" => "text", "text" => 'note "token": "x"' } ] }
      )

      result = McpExecutor.call(tool: @listing, environment_row: @row, arguments: {})

      assert_equal({ "project" => { "name" => "web", "token" => Redactions::REMOVED } }, JSON.parse(result["content"][0]["text"]))
      assert_equal "note \"token\": \"#{Redactions::REMOVED}\"", result["content"][1]["text"]
    end

    test "a listing is the answer as data, and a tool that is off, a refusal or an answer that is not data is a gap" do
      reader = Class.new(RemoteReader) { const_set(:NAME, "Acme") }
      answers = { "on" => { "content" => [ { "type" => "text", "text" => '[{"id":1}]' } ] },
                  "refused" => { "isError" => true, "content" => [ { "type" => "text", "text" => "403 forbidden" } ] },
                  "words" => { "content" => [ { "type" => "text", "text" => "no data here" } ] } }
      listing = reader.new { |name, _arguments, _reads| answers[name] }

      assert_equal [ { "id" => 1 } ], listing.listing("on", "projects", kinds: [ ResourceMap::KIND_SERVICE ])
      assert_nil listing.listing("off", "projects", kinds: [ ResourceMap::KIND_SERVICE ])
      assert_nil listing.listing("refused", "projects", kinds: [ ResourceMap::KIND_SERVICE ])
      assert_nil listing.listing("words", "projects", kinds: [ ResourceMap::KIND_SERVICE ])
      assert_equal [ "off is switched off for Acme, so the projects are not on the map.", "Acme refused to list the projects: 403 forbidden.",
                     "Acme answered the projects with something that is not JSON." ], listing.gaps.map(&:text)
      assert(listing.gaps.all? { |gap| gap.kinds == [ ResourceMap::KIND_SERVICE ] })
      assert_equal "Acme refused refused: 403 forbidden.", assert_raises(RemoteReader::Refused) { listing.refused!("refused", answers["refused"]) }.message
      assert_equal answers["on"], listing.refused!("on", answers["on"])
    end

    test "every provider's answer has anything that looks like a credential taken out, whatever the provider" do
      @listing.update!(name: "list_sources")
      Provider.stubs(:for).returns(Provider.new(key: "datadog"))
      McpClient.any_instance.stubs(:call_tool).returns(
        { "content" => [ { "type" => "text", "text" => "token ghp_#{'a' * 36} in the log" } ], "structuredContent" => { "line" => "key AKIA#{'B' * 16}" } }
      )

      result = McpExecutor.call(tool: @listing, environment_row: @row, arguments: {})

      assert_equal "token [REDACTED:github_token] in the log", result["content"].first["text"]
      assert_equal({ "line" => "key [REDACTED:aws_key]" }, result["structuredContent"])
    end
  end
end
