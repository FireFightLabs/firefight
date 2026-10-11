require "test_helper"

class Integrations::Capabilities::AwsReleasesTest < ActiveSupport::TestCase
  ACCOUNT = "123456789012".freeze
  SERVICE_ARN = "arn:aws:ecs:eu-west-1:#{ACCOUNT}:service/prod/web".freeze
  PIPELINE_ARN = "arn:aws:codepipeline:eu-west-1:#{ACCOUNT}:release-web".freeze
  GROUP_ARN = "arn:aws:codedeploy:eu-west-1:#{ACCOUNT}:deploymentgroup:shop/web-prod".freeze
  STACK_ARN = "arn:aws:cloudformation:eu-west-1:#{ACCOUNT}:stack/shop-infra/5b2c8e10".freeze
  APP_ARN = "arn:aws:apprunner:eu-west-1:#{ACCOUNT}:service/api/8fe1e103".freeze
  ENVIRONMENT_ARN = "arn:aws:elasticbeanstalk:eu-west-1:#{ACCOUNT}:environment/shop/shop-prod".freeze
  Caps = Integrations::Capabilities

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @aws = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "aws", name: "AWS", slug: "aws")
    @row = @aws.integration_environments.create!(catalog_entry_id: catalog_entries(:production_env).id, credentials: { access_key_id: "a" }.to_json)
    Integrations::Packs::Aws.tool_definitions.each do |definition|
      @aws.tools.create!(name: definition.name, description: definition.description, read_only: definition.read_only, enabled: true, params_schema: definition.params_schema)
    end
    { SERVICE_ARN => [ ResourceMap::KIND_SERVICE, "web" ], PIPELINE_ARN => [ ResourceMap::KIND_PIPELINE, "release-web" ],
      GROUP_ARN => [ ResourceMap::KIND_RELEASE_FLOW, "shop/web-prod" ], STACK_ARN => [ ResourceMap::KIND_STACK, "shop-infra" ],
      APP_ARN => [ ResourceMap::KIND_SERVICE, "api" ], ENVIRONMENT_ARN => [ ResourceMap::KIND_SERVICE, "shop-prod" ] }.each do |arn, (kind, name)|
      ResourceMap::Resource.create!(workspace: @workspace, provider: "aws", account: ACCOUNT, kind: kind, external_id: arn, name: name,
                                    integration_environment: @row, first_seen_at: Time.current, last_seen_at: Time.current)
    end
  end

  test "run history of a pipeline, a deployment group and a stack runs each one's own read, with the run asked for" do
    pipeline = resolve(Caps::HISTORY, "resource" => "release-web", "run" => "5d6a2b8e")
    assert_equal [ "pipeline_executions", { "resource" => PIPELINE_ARN, "limit" => 20, "run" => "5d6a2b8e" } ], [ pipeline.tool.name, pipeline.arguments ]
    assert_equal "codedeploy_deployments", resolve(Caps::HISTORY, "resource" => "shop/web-prod").tool.name
    assert_equal [ "stack_events", { "resource" => STACK_ARN, "limit" => 5, "name" => "update" } ],
                 resolve(Caps::HISTORY, "resource" => "shop-infra", "limit" => 5, "name" => "update").then { |call| [ call.tool.name, call.arguments ] }
  end

  test "an App Runner service and an Elastic Beanstalk environment answer status and deploys, and refuse the rest in words" do
    assert_equal [ "describe_app", { "resource" => APP_ARN } ], resolve(Caps::STATUS, "resource" => "api").then { |call| [ call.tool.name, call.arguments ] }
    assert_equal "app_runner_operations", resolve(Caps::HISTORY, "resource" => "api").tool.name
    assert_equal "beanstalk_events", resolve(Caps::DEPLOYS, "resource" => "shop-prod").tool.name
    assert_equal "api is an App Runner service. Firefight reads how it stands and what it deployed, and runs no metrics for it.",
                 unroutable(Caps::METRICS, "resource" => "api")
    assert_match "an Elastic Beanstalk environment, whose logs are in CloudWatch Logs", unroutable(Caps::LOGS, "resource" => "shop-prod")
    assert_match "runs no rollback for it", unroutable(Caps::ROLLBACK, "resource" => "api", "to" => "v1")
  end

  test "a rollback stops or undoes the release going now, and an ECS rollback to a revision goes as before" do
    revision = resolve(Caps::ROLLBACK, "resource" => "web", "to" => "web:41")
    assert_equal [ "rollback_deployment", { "resource" => SERVICE_ARN, "to" => "web:41" } ], [ revision.tool.name, revision.arguments ]
    assert_equal "rollback_deployment", resolve(Caps::ROLLBACK, "resource" => "web", "to" => "41").tool.name

    stopped = resolve(Caps::ROLLBACK, "resource" => "web", "to" => "NCWGC2ZR-taawPAYrIaU5")
    assert_equal [ "stop_service_deployment", { "resource" => SERVICE_ARN, "deployment" => "NCWGC2ZR-taawPAYrIaU5", "mode" => "rollback" } ],
                 [ stopped.tool.name, stopped.arguments ]

    stage = resolve(Caps::ROLLBACK, "resource" => "release-web", "to" => "Deploy:1a2b3c4d")
    assert_equal [ "rollback_pipeline_stage", { "resource" => PIPELINE_ARN, "stage" => "Deploy", "to" => "1a2b3c4d" } ], [ stage.tool.name, stage.arguments ]
    assert_equal({ "resource" => GROUP_ARN, "deployment" => "d-ABCDEF123", "roll_back" => true }, resolve(Caps::ROLLBACK, "resource" => "shop/web-prod", "to" => "d-ABCDEF123").arguments)
    assert_equal [ "cancel_stack_update", { "resource" => STACK_ARN, "operation" => "op-3" } ],
                 resolve(Caps::ROLLBACK, "resource" => "shop-infra", "to" => "op-3").then { |call| [ call.tool.name, call.arguments ] }
  end

  test "the release reads and rollbacks are wrapped, and stopping without rolling back stays offered" do
    adapter = Caps::Aws
    %w[pipeline_executions codedeploy_deployments stack_events app_runner_operations beanstalk_events describe_app rollback_pipeline_stage cancel_stack_update].each do |name|
      assert adapter.wraps?(name), name
    end
    %w[stop_service_deployment stop_codedeploy_deployment stop_pipeline_execution cloudwatch_metrics].each { |name| assert_not adapter.wraps?(name), name }
  end

  private

  def resolve(key, given) = Caps.resolve(@workspace, key, given, principal: map_reader)

  def unroutable(key, given)
    assert_raises(Caps::Unroutable) { resolve(key, given) }.message
  end
end
