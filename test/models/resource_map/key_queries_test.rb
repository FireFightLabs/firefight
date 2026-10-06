require "test_helper"

class ResourceMap::KeyQueriesTest < ActiveSupport::TestCase
  ACCOUNT = "123456789012".freeze
  FUNCTION_ARN = "arn:aws:lambda:eu-west-1:#{ACCOUNT}:function:checkout".freeze
  DATABASE_ARN = "arn:aws:rds:eu-west-1:#{ACCOUNT}:db:orders".freeze
  KEY_QUERIES = ResourceMap::KeyQueries

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

  test "every kind on the map has its checks or says why it has none, never both" do
    ResourceMap::KINDS.each do |kind|
      checks = KEY_QUERIES.for(kind)
      reason = KEY_QUERIES.none_reason(kind)
      assert checks.any? ^ reason.present?, "#{kind} needs checks or a reason, not both"
    end
    assert_empty KEY_QUERIES::BY_KIND.keys + KEY_QUERIES::NONE.keys - ResourceMap::KINDS
  end

  test "the kinds asked for carry the checks asked for" do
    assert_equal %w[error_rate latency_p95 cpu memory recent_deploys], keys(ResourceMap::KIND_SERVICE)
    assert_equal %w[cpu memory connections disk], keys(ResourceMap::KIND_DATABASE)
    assert_equal %w[invocations errors duration throttles], keys(ResourceMap::KIND_FUNCTION)
    assert_equal %w[availability], keys(ResourceMap::KIND_DOMAIN)
    assert_equal %w[availability recent_deploys], keys(ResourceMap::KIND_SITE)
  end

  test "each check only reads, through a capability, and names metrics from the shared vocabulary" do
    KEY_QUERIES::CHECKS.each_value do |check|
      spec = Integrations::Capabilities.spec(check.capability)
      assert_not spec.writes, "#{check.key} must only read"
      assert_empty check.metrics - Integrations::Capabilities::METRIC_NAMES
      assert_equal check.metric?, check.metrics.any?
    end
  end

  test "a check reads the first of its metrics the connection keeps, and names the one it cannot read" do
    invocations = KEY_QUERIES.plan(@function, KEY_QUERIES::CHECKS.fetch("invocations"), principal: @alice)
    assert_equal [ "invocations", "cloudwatch_metrics", %w[Invocations] ], [ invocations.metric, invocations.call.tool.name, invocations.call.arguments["metrics"] ]
    assert_equal({ "resource" => @function.id, "metrics" => [ "invocations" ], "minutes" => 30 }, invocations.arguments(30))

    duration = KEY_QUERIES.plan(@function, KEY_QUERIES::CHECKS.fetch("duration"), principal: @alice)
    assert_equal "duration", duration.metric

    disk = KEY_QUERIES.plan(@database, KEY_QUERIES::CHECKS.fetch("disk"), principal: @alice)
    assert_equal %w[FreeStorageSpace], disk.call.arguments["metrics"]

    latency = KEY_QUERIES.plan(@function, KEY_QUERIES::CHECKS.fetch("latency_p95"), principal: @alice)
    assert_not latency.available?
    assert_match "AWS does not keep latency_p95 for this resource", latency.refusal
  end

  test "whether a check can run is worked out live, so switching its tool off takes it away" do
    @aws.tools.find_by!(name: "cloudwatch_metrics").update!(enabled: false)

    plan = KEY_QUERIES.plan(@function, KEY_QUERIES::CHECKS.fetch("throttles"), principal: @alice)

    assert_not plan.available?
    assert_match "switched off", plan.refusal
  end

  test "a person who may not run the tool sees the check with why, and an admin may run it" do
    listed = KEY_QUERIES.listed(@function, @bob)
    throttles = listed.find { |each| each.plan.check.key == "throttles" }
    assert_match "Running it calls aws.cloudwatch_metrics on AWS, which you have not been granted", throttles.run_blocked_reason
    assert_nil KEY_QUERIES.listed(@function, @alice).find { |each| each.plan.check.key == "throttles" }.run_blocked_reason
  end

  test "a reading is compared with the normal the answering connection read for that metric" do
    record_baseline(@function, "Throttles", [ 0.0, 1.0, 2.0, 2.0 ])
    plan = KEY_QUERIES.plan(@function, KEY_QUERIES::CHECKS.fetch("throttles"), principal: @alice)
    assert_equal "usually 1.5 per minute, 95% under 2 per minute", plan.baseline.normal_text

    result = chart_result("per minute", [ [ 1.0, 9.0 ] ])
    assert_equal "Throttles of checkout, from AWS. Now 9 per minute, 4.5x the usual high of 2 per minute (usually 1.5 per minute).",
                 KEY_QUERIES.headline(plan.check, plan.call, plan.metric, result)
    assert_match "No normal is known for it yet, since AWS has not read a week of invocations for checkout",
                 KEY_QUERIES.verdict(KEY_QUERIES::CHECKS.fetch("invocations"), plan.call, "invocations", result)
    assert_match "No reading came back for throttles", KEY_QUERIES.verdict(plan.check, plan.call, "throttles", { "content" => [] })
    assert_nil KEY_QUERIES.verdict(KEY_QUERIES::CHECKS.fetch("recent_deploys"), plan.call, nil, result)
  end

  test "running a check from the map is authorized and ledgered as the provider tool, from the web, with the comparison" do
    record_baseline(@function, "Throttles", [ 0.0, 1.0, 2.0, 2.0 ])
    Integrations::NativeExecutor.expects(:call).with { |tool:, arguments:, **| tool.name == "cloudwatch_metrics" && arguments["metrics"] == %w[Throttles] && arguments["minutes"] == 60 }
                                .returns(chart_result("per minute", [ [ 1.0, 9.0 ] ]).merge("content" => [ { "type" => "text", "text" => "Throttles of checkout" } ]))

    outcome = KEY_QUERIES.run!(@function, KEY_QUERIES::CHECKS.fetch("throttles"), principal: @alice)

    assert_match "4.5x the usual high", outcome.headline
    assert_equal [ "Throttles of checkout", false, 1 ], [ outcome.text, outcome.failed, outcome.charts.size ]
    invocation = Ability::Invocation.find_by!(workspace: @workspace, action_key: "aws.cloudwatch_metrics")
    assert_equal AbilityGateway::SOURCE_WEB, invocation.source
  end

  test "a person without the grant is refused through the gateway, and nothing is called" do
    Integrations::NativeExecutor.expects(:call).never

    outcome = KEY_QUERIES.run!(@function, KEY_QUERIES::CHECKS.fetch("throttles"), principal: @bob)

    assert_match "You may not run aws.cloudwatch_metrics here", outcome.refusal
    assert Ability::Invocation.exists?(workspace: @workspace, action_key: "aws.cloudwatch_metrics", decision: Ability::Invocation::DECISION_DENY)
  end

  test "a provider's own failure is an answer that failed" do
    Integrations::NativeExecutor.expects(:call).raises(Integrations::Error, "AWS answered 400: throttled")

    outcome = KEY_QUERIES.run!(@database, KEY_QUERIES::CHECKS.fetch("cpu"), principal: @alice)

    assert outcome.failed
    assert_match "aws.cloudwatch_metrics failed: AWS answered 400: throttled", outcome.text
  end

  test "a check a kind does not have is named with the ones it has" do
    assert_equal "checkout has no disk check. Its checks are invocations, errors, duration, and throttles.", KEY_QUERIES.unknown(@function, "disk")
    bucket = resource!(ResourceMap::KIND_BUCKET, "arn:aws:s3:::assets", "assets")
    assert_match "assets has no checks. No connected provider says how one stands", KEY_QUERIES.unknown(bucket, "cpu")
  end

  private

  def keys(kind) = KEY_QUERIES.for(kind).map(&:key)

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
