require "test_helper"

class Integrations::Capabilities::PosthogTest < ActiveSupport::TestCase
  QUERY_BODY = { "type" => "object", "properties" => { "query" => { "type" => "object" } }, "required" => [ "query" ] }.freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    northflank = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank", slug: "northflank")
    @northflank_row = northflank.integration_environments.create!(catalog_entry_id: catalog_entries(:production_env).id, credentials: { token: "x" }.to_json)
    %w[search_logs describe_resource].each do |name|
      northflank.tools.create!(name: name, description: name, read_only: true, enabled: true, params_schema: { "type" => "object" })
    end
    posthog = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "posthog", name: "PostHog", slug: "posthog",
                                              settings: { "server_url" => IntegrationProvider.find("posthog").server_url, "region" => "us" })
    @posthog_row = posthog.integration_environments.create!
    @logs = posthog.tools.create!(name: "query_logs", description: "Logs", read_only: true, enabled: true, params_schema: QUERY_BODY,
                                  spec: { "tool_name" => "query-logs" })
    posthog.tools.create!(name: "query_apm_spans", description: "Spans", read_only: true, enabled: true, params_schema: QUERY_BODY,
                          spec: { "tool_name" => "query-apm-spans" })
    ResourceMap::Resource.create!(workspace: @workspace, provider: "northflank", account: "team/prod", kind: ResourceMap::KIND_SERVICE, external_id: "web-id",
                                  name: "web", integration_environment: @northflank_row, first_seen_at: Time.current, last_seen_at: Time.current)
  end

  test "PostHog answers logs for a service Northflank runs by its service name, newest first, with the filters on the log body" do
    logs = resolve(Integrations::Capabilities::LOGS, "resource" => "web", "text" => "timeout", "regex" => "5\\d\\d", "exclude" => "health", "minutes" => 30, "limit" => 5000)

    assert_equal [ @posthog_row, "query_logs" ], [ logs.environment_row, logs.tool.name ]
    assert_equal({ "orderBy" => "latest", "serviceNames" => [ "web" ], "dateRange" => { "date_from" => "-30M" }, "limit" => 1000,
                   "filterGroup" => [ { "type" => "log", "key" => "message", "operator" => "icontains", "value" => "timeout" },
                                      { "type" => "log", "key" => "message", "operator" => "regex", "value" => "5\\d\\d" },
                                      { "type" => "log", "key" => "message", "operator" => "not_icontains", "value" => "health" } ] },
                 logs.arguments.fetch("query"))
    assert_equal @northflank_row, logs.fallback.environment_row
  end

  test "whole hours read as hours, the default is the last hour, and a start and end are sent as they are" do
    assert_equal({ "date_from" => "-2h" }, resolve(Integrations::Capabilities::LOGS, "resource" => "web", "minutes" => 120).arguments.dig("query", "dateRange"))
    assert_equal({ "date_from" => "-1h" }, resolve(Integrations::Capabilities::LOGS, "resource" => "web").arguments.dig("query", "dateRange"))

    asked = resolve(Integrations::Capabilities::LOGS, "resource" => "web", "start" => "2026-09-01T10:00:00Z", "end" => "2026-09-01T11:00:00Z")
    assert_equal({ "date_from" => "2026-09-01T10:00:00Z", "date_to" => "2026-09-01T11:00:00Z" }, asked.arguments.dig("query", "dateRange"))
    assert_not asked.arguments.fetch("query").key?("limit")
  end

  test "PostHog answers traces with the service's own spans, slowest first, root or not" do
    traces = resolve(Integrations::Capabilities::TRACES, "resource" => "web", "text" => "checkout", "limit" => 20)

    assert_equal [ @posthog_row, "query_apm_spans" ], [ traces.environment_row, traces.tool.name ]
    assert_equal({ "orderBy" => "duration", "orderDirection" => "DESC", "flatSpans" => true, "rootSpans" => false, "serviceNames" => [ "web" ],
                   "filterGroup" => [ { "type" => "span", "key" => "name", "operator" => "icontains", "value" => "checkout" } ],
                   "dateRange" => { "date_from" => "-1h" }, "limit" => 20 }, traces.arguments.fetch("query"))
  end

  test "a stream other than what the app prints is the platform's, and asked of PostHog by name it says why" do
    assert_equal @northflank_row, resolve(Integrations::Capabilities::LOGS, "resource" => "web", "stream" => "build").environment_row
    assert_match "stream must be app", unroutable(Integrations::Capabilities::LOGS, "resource" => "web", "stream" => "build", "connection" => "posthog")
    assert_equal @posthog_row, resolve(Integrations::Capabilities::LOGS, "resource" => "web", "stream" => "app").environment_row
  end

  test "a tool that no longer takes its arguments inside query is refused with words, never guessed" do
    @logs.update!(params_schema: { "type" => "object", "properties" => { "serviceNames" => {} } })

    assert_match "takes its arguments in a way Firefight does not know", unroutable(Integrations::Capabilities::LOGS, "resource" => "web", "connection" => "posthog")
  end

  test "an empty answer reads as nothing, so the platform is asked, and an answer with rows is kept as it came" do
    present = resolve(Integrations::Capabilities::LOGS, "resource" => "web").present
    link = Integrations::Telemetry.link_line(Integrations::Telemetry::Link.new(provider: "PostHog", url: "https://us.posthog.com/project/1/logs"))
    empty = { "content" => [ { "type" => "text", "text" => "results: []\n\nNo log rows matched. If this project has never ingested logs, load the `instrument-logs` skill." },
                             { "type" => "text", "text" => link } ] }

    presented = present.call(empty)
    assert_equal [ { "results" => [] }.to_json, link ], presented["content"].map { |part| part["text"] }
    assert_not Integrations::Capabilities.definitive?(presented)

    rows = { "content" => [ { "type" => "text", "text" => "results[1]:\n  - body: upstream timeout\n    severity_text: error" } ] }
    assert_equal rows, present.call(rows)
    assert Integrations::Capabilities.definitive?(present.call(rows))
    failed = { "isError" => true, "content" => [ { "type" => "text", "text" => "results: []" } ] }
    assert_equal failed, present.call(failed)
  end

  test "Halon's sentence says PostHog answers for the services it watches" do
    sentence = Integrations::Capabilities.halon_sentence("posthog", "PostHog")

    assert_match "read its logs and read its traces", sentence
    assert_match "the services on the map that PostHog watches", sentence
  end

  private

  def resolve(key, given) = Integrations::Capabilities.resolve(@workspace, key, given)

  def unroutable(key, given) = assert_raises(Integrations::Capabilities::Unroutable) { resolve(key, given) }.message
end
