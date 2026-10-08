require "test_helper"

class Integrations::Capabilities::AwsTest < ActiveSupport::TestCase
  ACCOUNT = "123456789012".freeze
  SERVICE_ARN = "arn:aws:ecs:eu-west-1:#{ACCOUNT}:service/prod/web".freeze
  FUNCTION_ARN = "arn:aws:lambda:eu-west-1:#{ACCOUNT}:function:checkout".freeze
  INSTANCE_ARN = "arn:aws:ec2:eu-west-1:#{ACCOUNT}:instance/i-0abc".freeze
  DATABASE_ARN = "arn:aws:rds:eu-west-1:#{ACCOUNT}:db:orders".freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @aws = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "aws", name: "AWS", slug: "aws")
    @row = @aws.integration_environments.create!(catalog_entry_id: catalog_entries(:production_env).id, credentials: { access_key_id: "a" }.to_json)
    @tools = Integrations::Packs::Aws.tool_definitions.to_h do |definition|
      [ definition.name, @aws.tools.create!(name: definition.name, description: definition.description, read_only: definition.read_only, enabled: true,
                                            params_schema: definition.params_schema) ]
    end
    { SERVICE_ARN => [ ResourceMap::KIND_SERVICE, "web" ], FUNCTION_ARN => [ ResourceMap::KIND_FUNCTION, "checkout" ],
      INSTANCE_ARN => [ ResourceMap::KIND_VIRTUAL_MACHINE, "bastion" ], DATABASE_ARN => [ ResourceMap::KIND_DATABASE, "orders" ] }.each do |arn, (kind, name)|
      ResourceMap::Resource.create!(workspace: @workspace, provider: "aws", account: ACCOUNT, kind: kind, external_id: arn, name: name,
                                    integration_environment: @row, first_seen_at: Time.current, last_seen_at: Time.current)
    end
  end

  test "each read runs AWS's own tool by the resource's ARN, with the arguments it was given" do
    logs = resolve(Integrations::Capabilities::LOGS, "resource" => "web", "text" => "timeout", "minutes" => 30, "stream" => "app")
    assert_equal [ "search_logs", { "resource" => SERVICE_ARN, "text" => "timeout", "minutes" => 30 } ], [ logs.tool.name, logs.arguments ]

    status = resolve(Integrations::Capabilities::STATUS, "resource" => "orders")
    assert_equal [ "describe_resource", { "resource" => DATABASE_ARN } ], [ status.tool.name, status.arguments ]

    deploys = resolve(Integrations::Capabilities::DEPLOYS, "resource" => "checkout", "limit" => 5)
    assert_equal [ "list_deployments", { "resource" => FUNCTION_ARN, "limit" => 5 } ], [ deploys.tool.name, deploys.arguments ]
  end

  test "metric names map onto the CloudWatch metric AWS documents for each kind, and one it does not keep is named" do
    service = resolve(Integrations::Capabilities::METRICS, "resource" => "web", "metrics" => %w[cpu memory], "minutes" => 30)
    assert_equal [ "cloudwatch_metrics", { "resource" => SERVICE_ARN, "metrics" => %w[CPUUtilization MemoryUtilization], "minutes" => 30 } ], [ service.tool.name, service.arguments ]

    assert_equal %w[Invocations Errors], resolve(Integrations::Capabilities::METRICS, "resource" => "checkout", "metrics" => %w[requests errors]).arguments["metrics"]
    assert_equal %w[DatabaseConnections], resolve(Integrations::Capabilities::METRICS, "resource" => "orders", "metrics" => %w[tcp_connections]).arguments["metrics"]
    assert_equal({ "resource" => INSTANCE_ARN }, resolve(Integrations::Capabilities::METRICS, "resource" => "bastion").arguments)
    assert_match "AWS does not keep http_5xx for this resource. It keeps cpu, memory", unroutable(Integrations::Capabilities::METRICS, "resource" => "web", "metrics" => [ "http_5xx" ])
  end

  test "a function's invocations, duration and throttles and a database's memory and disk are the CloudWatch metrics AWS keeps, compared with their baselines" do
    function = resolve(Integrations::Capabilities::METRICS, "resource" => "checkout", "metrics" => %w[invocations duration throttles])
    assert_equal %w[Invocations Duration Throttles], function.arguments["metrics"]
    assert_equal %w[FreeableMemory FreeStorageSpace], resolve(Integrations::Capabilities::METRICS, "resource" => "orders", "metrics" => %w[memory disk]).arguments["metrics"]
    assert_match "AWS does not keep latency_p95", unroutable(Integrations::Capabilities::METRICS, "resource" => "checkout", "metrics" => [ "latency_p95" ])

    assert_equal "Throttles", Integrations::Capabilities.baseline_metric(@row, "throttles", ResourceMap::KIND_FUNCTION)
    assert_equal "FreeStorageSpace", Integrations::Capabilities.baseline_metric(@row, "disk", ResourceMap::KIND_DATABASE)
    assert_nil Integrations::Capabilities.baseline_metric(@row, "disk", ResourceMap::KIND_SERVICE)
    assert_includes Integrations::Packs::Aws::BASELINE_METRICS.fetch(ResourceMap::KIND_DATABASE), "FreeStorageSpace"
    Integrations::Capabilities::Aws::METRIC_MAP.each_value do |mapping|
      assert_empty mapping.keys - Integrations::Capabilities::METRIC_NAMES
      assert_empty mapping.values - Integrations::Packs::Aws::METRIC_NAMES
    end
  end

  test "a change runs the pack's tool for that change, with what it takes" do
    rollback = resolve(Integrations::Capabilities::ROLLBACK, "resource" => "web", "to" => "web:41")
    assert_equal [ "rollback_deployment", { "resource" => SERVICE_ARN, "to" => "web:41" } ], [ rollback.tool.name, rollback.arguments ]

    assert_equal [ "restart_service", { "resource" => SERVICE_ARN } ], resolve(Integrations::Capabilities::RESTART, "resource" => "web").then { |call| [ call.tool.name, call.arguments ] }
    scale = resolve(Integrations::Capabilities::SCALE, "resource" => "web", "instances" => 4)
    assert_equal [ "scale_service", { "resource" => SERVICE_ARN, "desired_count" => 4 } ], [ scale.tool.name, scale.arguments ]
    assert_equal({ "resource" => FUNCTION_ARN, "to" => "live:11" }, resolve(Integrations::Capabilities::ROLLBACK, "resource" => "checkout", "to" => "live:11").arguments)
  end

  test "an ECS service's run history is its deployments, and a Lambda function, whose versions keep no finish, has none" do
    history = resolve(Integrations::Capabilities::HISTORY, "resource" => "web")
    assert_equal [ "list_deployments", { "resource" => SERVICE_ARN, "limit" => Integrations::Capabilities::History::LIMIT } ], [ history.tool.name, history.arguments ]
    assert_match "no connection offers run history", unroutable(Integrations::Capabilities::HISTORY, "resource" => "checkout")
  end

  test "what AWS does not hold for a kind is said, never guessed" do
    assert_match "stream must be app", unroutable(Integrations::Capabilities::LOGS, "resource" => "web", "stream" => "build")
    assert_match "no connection offers logs", unroutable(Integrations::Capabilities::LOGS, "resource" => "bastion")
    assert_match "no connection offers a restart", unroutable(Integrations::Capabilities::RESTART, "resource" => "checkout")
    assert_match "no connection offers deploys", unroutable(Integrations::Capabilities::DEPLOYS, "resource" => "orders")
    assert_match "Say what to roll back to", unroutable(Integrations::Capabilities::ROLLBACK, "resource" => "web")
  end

  test "Halon is offered the capabilities in place of the tools they wrap, and keeps cloudwatch_metrics, which reads more" do
    assert Integrations::Capabilities.wrapped?(@tools["search_logs"])
    assert Integrations::Capabilities.wrapped?(@tools["rollback_deployment"])
    assert_not Integrations::Capabilities.wrapped?(@tools["cloudwatch_metrics"])
    assert_not Integrations::Capabilities.wrapped?(@tools["logs_insights_query"])
    assert_match "roll a resource back, restart a service, and scale a service for anything AWS runs", Integrations::Capabilities.halon_sentence("aws", "AWS")
  end

  test "an investigation is never offered a change on AWS, while its reads are" do
    investigation = @workspace.investigations.create!(subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_COMMAND,
                                                      max_turns: 10, max_spend_cents: 400)
    principal = investigation.acting_principal
    @tools.each_value { |tool| Ability::Grant.create!(workspace: @workspace, principal: principal, action: tool.reload.ability_action) }
    Ability::Resolver.bust!(principal_type: principal.class.polymorphic_name, principal_id: principal.id, workspace_id: @workspace.id)

    entries = Chat::Tools.catalog(investigation).index_by(&:name)

    %w[rollback restart scale].each { |name| assert_equal [ Chat::Tools::STATE_READS_ONLY, nil ], [ entries[name].state, entries[name].tool ], name }
    %w[aws_rollback_deployment aws_restart_service aws_scale_service].each { |name| assert(entries[name].nil? || entries[name].state == Chat::Tools::STATE_READS_ONLY, name) }
    assert_equal Chat::Tools::STATE_READY, entries["search_logs"].state
    assert_equal Chat::Tools::STATE_READY, entries["aws_cloudwatch_metrics"].state
    assert_equal Chat::Tools::STATE_READY, entries["aws_logs_insights_query"].state
  end

  private

  def resolve(key, given) = Integrations::Capabilities.resolve(@workspace, key, given, principal: map_reader)

  def unroutable(key, given)
    assert_raises(Integrations::Capabilities::Unroutable) { resolve(key, given) }.message
  end
end
