require "test_helper"

class Chat::Tools::KeyQueryTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @investigation = @workspace.investigations.create!(subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_COMMAND,
                                                       max_turns: 10, max_spend_cents: 400)
    northflank = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank", slug: "northflank")
    @row = northflank.integration_environments.create!(catalog_entry_id: catalog_entries(:production_env).id, credentials: { token: "x" }.to_json)
    @tools = %w[query_metrics list_deployments search_logs].index_with do |name|
      northflank.tools.create!(name: name, description: name, read_only: true, enabled: true, params_schema: { "type" => "object" })
    end
    @web = ResourceMap::Resource.create!(workspace: @workspace, provider: "northflank", account: "team/prod", kind: ResourceMap::KIND_SERVICE,
                                         external_id: "web-id", name: "web", integration_environment: @row, first_seen_at: Time.current, last_seen_at: Time.current)
  end

  test "Halon is offered run_key_query beside the capabilities, in the map's group, once it may run one they read through" do
    entry = catalog_entry
    assert_equal [ Chat::Tools::STATE_NOT_GRANTED, Chat::Tools::Groups::RESOURCES ], [ entry.state, entry.group ]

    grant!(@tools.values)
    assert_equal Chat::Tools::STATE_READY, catalog_entry.state
  end

  test "a check runs as its capability, authorized and ledgered as the provider's own tool, led by how it compares with normal" do
    grant!(@tools.values)
    ResourceMap::Baseline.record!(@row, [ @web ], [ ResourceMap::Baseline::Found.new(key: @web.key, metric: "http5xxResponses", label: "5xx responses",
                                                                                      unit: "per minute", points: [ [ 1.hour.ago, 1.0 ], [ 2.hours.ago, 2.0 ] ]) ],
                                  window_from: 7.days.ago, window_to: Time.current)
    chart = { "title" => "5xx responses", "unit" => "per minute", "from" => 1.hour.ago.iso8601, "to" => Time.current.iso8601,
              "series" => [ { "label" => "web", "points" => [ [ Time.current.iso8601, 10.0 ] ] } ] }
    Integrations::NativeExecutor.expects(:call).with { |tool:, arguments:, **| tool.name == "query_metrics" && arguments == { "resource" => "web-id", "metrics" => [ "http5xxResponses" ], "minutes" => 15 } }
                                .returns("content" => [ { "type" => "text", "text" => "5xx responses of web" } ], "structuredContent" => { "charts" => [ chart ] })

    answer = catalog_entry.tool.call("resource" => "web", "query" => "error_rate", "minutes" => 15)

    assert_match "Error rate of web, read as 5xx responses, from Northflank. Now 10 per minute, 5.1x the usual high of 1.95 per minute", answer
    assert_match "5xx responses of web", answer
    step = @investigation.steps.find_by!(tool_name: "query_metrics")
    assert_equal [ "northflank.query_metrics", { "resource" => "web-id", "metrics" => [ "http5xxResponses" ], "minutes" => 15 } ], [ step.action_key, step.params ]
  end

  test "a check the kind does not have, a resource not on the map, and one no connection keeps are refused in words" do
    grant!(@tools.values)
    tool = catalog_entry.tool

    assert_match "web has no throttles check. Its checks are error_rate, latency_p95, cpu, memory, and recent_deploys", tool.call("resource" => "web", "query" => "throttles")
    assert_match "Nothing on the resource map is called nope", tool.call("resource" => "nope", "query" => "cpu")
    assert_match "Northflank does not keep latency_p95", tool.call("resource" => "web", "query" => "latency_p95")
  end

  private

  def catalog_entry = Chat::Tools.catalog(@investigation).find { |entry| entry.name == "run_key_query" }

  def grant!(tools)
    principal = @investigation.acting_principal
    tools.each { |tool| Ability::Grant.create!(workspace: @workspace, principal: principal, action: tool.reload.ability_action) }
    Ability::Resolver.bust!(principal_type: principal.class.polymorphic_name, principal_id: principal.id, workspace_id: @workspace.id)
  end
end
