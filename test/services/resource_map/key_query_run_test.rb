require "test_helper"

class ResourceMap::KeyQueryRunTest < ActiveSupport::TestCase
  ACCOUNT = "123456789012".freeze
  FUNCTION_ARN = "arn:aws:lambda:eu-west-1:#{ACCOUNT}:function:checkout".freeze
  DATABASE_ARN = "arn:aws:rds:eu-west-1:#{ACCOUNT}:db:orders".freeze
  CHECKS = ResourceMap::KeyQueries::CHECKS

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    @aws = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "aws", name: "AWS", slug: "aws")
    @row = @aws.integration_environments.create!(catalog_entry_id: catalog_entries(:production_env).id, credentials: { access_key_id: "a" }.to_json)
    Integrations::Packs::Aws.tool_definitions.each do |definition|
      @aws.tools.create!(name: definition.name, description: definition.description, read_only: definition.read_only, enabled: true,
                         params_schema: definition.params_schema)
    end
    @function = resource!(ResourceMap::KIND_FUNCTION, FUNCTION_ARN, "checkout")
    @database = resource!(ResourceMap::KIND_DATABASE, DATABASE_ARN, "orders")
  end

  test "running a check from the map is authorized and ledgered as the provider tool, from the web, with the comparison" do
    record_baseline(@function, "Throttles", [ 0.0, 1.0, 2.0, 2.0 ])
    Integrations::NativeExecutor.expects(:call).with { |tool:, arguments:, **| tool.name == "cloudwatch_metrics" && arguments["metrics"] == %w[Throttles] && arguments["minutes"] == 60 }
                                .returns(chart_result("per minute", [ [ 1.0, 9.0 ] ]).merge("content" => [ { "type" => "text", "text" => "Throttles of checkout" } ]))

    outcome = ResourceMap::KeyQueryRun.call(@function, CHECKS.fetch("throttles"), principal: @alice)

    assert_match "4.5x the usual high", outcome.headline
    assert_equal [ "Throttles of checkout", false, 1 ], [ outcome.text, outcome.failed, outcome.charts.size ]
    invocation = Ability::Invocation.find_by!(workspace: @workspace, action_key: "aws.cloudwatch_metrics")
    assert_equal AbilityGateway::SOURCE_WEB, invocation.source
  end

  test "a person without the grant is refused through the gateway, and nothing is called" do
    take_aws_reads_from_bob
    Integrations::NativeExecutor.expects(:call).never

    outcome = ResourceMap::KeyQueryRun.call(@function, CHECKS.fetch("throttles"), principal: @bob)

    assert_match "You may not run aws.cloudwatch_metrics here", outcome.refusal
    assert Ability::Invocation.exists?(workspace: @workspace, action_key: "aws.cloudwatch_metrics", decision: Ability::Invocation::DECISION_DENY)
  end

  test "a provider's own failure is an answer that failed" do
    Integrations::NativeExecutor.expects(:call).raises(Integrations::Error, "AWS answered 400: throttled")

    outcome = ResourceMap::KeyQueryRun.call(@database, CHECKS.fetch("cpu"), principal: @alice)

    assert outcome.failed
    assert_match "aws.cloudwatch_metrics failed: AWS answered 400: throttled", outcome.text
  end

  private

  # Every member reads every connected tool, so an admin takes AWS's reads away for this one.
  def take_aws_reads_from_bob
    Ability::Grant.withhold!(workspace: @workspace, principal: @bob, role: @aws.permission_packs.find_by!(pack: Ability::Role::PACK_READ))
  end

  def resource!(kind, id, name)
    ResourceMap::Resource.create!(workspace: @workspace, provider: "aws", account: ACCOUNT, kind: kind, external_id: id, name: name,
                                  integration_environment: @row, first_seen_at: Time.current, last_seen_at: Time.current)
  end

  def record_baseline(resource, metric, values)
    to = Time.current
    points = values.each_with_index.map { |value, index| [ to - index.hours, value ] }
    ResourceMap::Baseline.record!(@row, [ resource ], [ ResourceMap::Baseline::Found.new(key: resource.key, metric: metric, label: metric, unit: "per minute", points: points) ],
                                  window_from: to - 7.days, window_to: to)
  end

  def chart_result(unit, series_values)
    series = series_values.each_with_index.map do |values, index|
      { "label" => "s#{index}", "points" => values.each_with_index.map { |value, offset| [ (Time.current - (values.size - offset).minutes).iso8601, value ] } }
    end
    { Integrations::Telemetry::STRUCTURED => { Integrations::Telemetry::CHARTS => [ { "title" => "Throttles", "unit" => unit, "from" => 1.hour.ago.iso8601,
                                                                                     "to" => Time.current.iso8601, "series" => series } ] } }
  end
end
