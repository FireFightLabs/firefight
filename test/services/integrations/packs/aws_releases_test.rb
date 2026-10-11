require "test_helper"

module Integrations
  module Packs
    # Answers are written from the shapes the API references of CodePipeline (PipelineExecutionSummary,
    # ActionExecutionDetail), CodeDeploy (DeploymentInfo, DeploymentTarget), CloudFormation (Stack, StackEvent), ECS
    # (ServiceDeployment), App Runner (OperationSummary) and Elastic Beanstalk (EventDescription) give.
    class AwsReleasesTest < ActiveSupport::TestCase
      ACCOUNT = "123456789012".freeze
      REGION = "eu-west-1".freeze
      SERVICE_ARN = "arn:aws:ecs:#{REGION}:#{ACCOUNT}:service/prod/web".freeze
      PIPELINE_ARN = "arn:aws:codepipeline:#{REGION}:#{ACCOUNT}:release-web".freeze
      GROUP_ARN = "arn:aws:codedeploy:#{REGION}:#{ACCOUNT}:deploymentgroup:shop/web-prod".freeze
      STACK_ARN = "arn:aws:cloudformation:#{REGION}:#{ACCOUNT}:stack/shop-infra/5b2c8e10-0000-11ef-9a1b-0a1b2c3d4e5f".freeze
      APP_ARN = "arn:aws:apprunner:#{REGION}:#{ACCOUNT}:service/api/8fe1e10304f84fd2b0df550fe98a71fa".freeze
      ENVIRONMENT_ARN = "arn:aws:elasticbeanstalk:#{REGION}:#{ACCOUNT}:environment/shop/shop-prod".freeze
      EXECUTION = "5d6a2b8e-0c3f-4b7a-9e21-6f0d3c2b1a90".freeze
      EARLIER = "1a2b3c4d-1111-4b7a-9e21-6f0d3c2b1a90".freeze
      History = Capabilities::History

      setup do
        @workspace = workspaces(:slack_workspace_one)
        @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "aws", name: "AWS")
        @row = @integration.integration_environments.create!
        Aws.store_credentials!(@row, Aws::ACCESS_KEY_ID => "AKIAEXAMPLE", Aws::SECRET_ACCESS_KEY => "secret")
        @row.store_fields!(Aws::REGIONS => [ REGION ])
        @pack = Aws.new(@integration)
        AwsApi.any_instance.stubs(:identity).returns(account: ACCOUNT)
      end

      test "pipelines, deployment groups and stacks are on the map with how their last run went, linked to what they release" do
        listing(:list_clusters, [ "arn:aws:ecs:#{REGION}:#{ACCOUNT}:cluster/prod" ])
        listing(:list_services, [ SERVICE_ARN ], service: :ecs)
        %i[list_functions describe_instances describe_db_instances list_applications list_projects].each { |operation| listing(operation, []) }
        listing(:list_services, [ { service_arn: APP_ARN, service_name: "api", status: "OPERATION_IN_PROGRESS", service_url: "abc.eu-west-1.awsapprunner.com" } ], service: :apprunner)
        listing(:describe_environments, [ { environment_arn: ENVIRONMENT_ARN, environment_name: "shop-prod", application_name: "shop", status: "Ready", health: "Red" } ])
        listing(:list_pipelines, [ { name: "release-web" } ])
        listing(:list_applications, [ "shop" ], service: :codedeploy)
        listing(:list_deployment_groups, [ "web-prod" ])
        listing(:describe_stacks, [ { stack_id: STACK_ARN, stack_name: "shop-infra", stack_status: "UPDATE_ROLLBACK_COMPLETE" },
                                    { stack_id: "#{STACK_ARN}x", stack_name: "gone", stack_status: "DELETE_COMPLETE" } ])
        answer(:describe_services, services: [ { service_arn: SERVICE_ARN, service_name: "web", cluster_arn: "arn:aws:ecs:#{REGION}:#{ACCOUNT}:cluster/prod",
                                                 status: "ACTIVE", desired_count: 1, running_count: 1, deployments: [],
                                                 tags: [ { key: Aws::Releases::STACK_TAG, value: STACK_ARN } ] } ])
        answer(:describe_task_definition, task_definition: {})
        answer(:get_pipeline, pipeline: pipeline_definition)
        answer(:list_pipeline_executions, pipeline_execution_summaries: [ { pipeline_execution_id: EXECUTION, status: "InProgress" } ])
        answer(:batch_get_deployment_groups, deployment_groups_info: [ { deployment_group_name: "web-prod", compute_platform: "ECS",
                                                                         ecs_services: [ { service_name: "web", cluster_name: "prod" } ],
                                                                         last_attempted_deployment: { deployment_id: "d-ABCDEF123", status: "Failed" } } ])

        snapshot = @pack.map_of(@row)

        found = snapshot.resources.index_by(&:external_id)
        assert_equal [ ResourceMap::KIND_PIPELINE, "release-web", "in_progress" ], found[PIPELINE_ARN].then { |each| [ each.kind, each.name, each.status ] }
        assert_equal [ ResourceMap::KIND_RELEASE_FLOW, "shop/web-prod", "failed", "ECS" ], found[GROUP_ARN].then { |each| [ each.kind, each.name, each.status, each.details["type"] ] }
        assert_equal [ ResourceMap::KIND_STACK, "shop-infra", "update_rollback_complete" ], found[STACK_ARN].then { |each| [ each.kind, each.name, each.status ] }
        assert_not found.key?("#{STACK_ARN}x"), "a deleted stack is not on the map"
        assert_equal [ ResourceMap::KIND_SERVICE, "in_progress", "App Runner" ], found[APP_ARN].then { |each| [ each.kind, each.status, each.details["type"] ] }
        assert_equal [ ResourceMap::KIND_SERVICE, "unhealthy", "shop" ], found[ENVIRONMENT_ARN].then { |each| [ each.kind, each.status, each.details["application"] ] }
        assert_equal "https://eu-west-1.console.aws.amazon.com/apprunner/home?region=eu-west-1", found[APP_ARN].url

        released = snapshot.links.select { |link| link.relation == ResourceMap::RELATION_RELEASED_BY }.map { |link| [ link.from.last, link.to.last ] }
        assert_includes released, [ SERVICE_ARN, PIPELINE_ARN ], "the pipeline's ECS action names the service"
        assert_includes released, [ GROUP_ARN, PIPELINE_ARN ], "its CodeDeploy action names the group"
        assert_includes released, [ STACK_ARN, PIPELINE_ARN ], "its CloudFormation action names the stack"
        assert_includes released, [ ENVIRONMENT_ARN, PIPELINE_ARN ], "its Elastic Beanstalk action names the environment"
        assert_includes released, [ SERVICE_ARN, GROUP_ARN ], "the group lists the service"
        assert_includes released, [ SERVICE_ARN, STACK_ARN ], "CloudFormation tagged the service with the stack's id"
        assert snapshot.complete?

        assert_equal "success", Provider.for("aws").status_words["succeeded"]
        assert_equal ResourceMap::Resource::HEALTH_FAILING, ResourceMap::Resource.new(status: Provider.for("aws").status_words["update_rollback_complete"]).health
      end

      test "a list AWS refuses is a gap naming its kind, and slowing down ends the read where it was" do
        AwsApi.any_instance.stubs(:all).returns([ [], false ])
        AwsApi.any_instance.stubs(:all).with { |service, *| service == :codedeploy }.raises(AwsApi::Denied, "AWS answered AccessDeniedException: codedeploy:ListApplications")

        assert_equal [ ResourceMap::KIND_RELEASE_FLOW ], @pack.map_of(@row).unread_kinds

        AwsApi.any_instance.stubs(:all).with { |service, *| service == :apprunner }.raises(AwsApi::RateLimited, "AWS answered ThrottlingException: Rate exceeded")
        AwsApi.any_instance.expects(:all).with { |service, *| service == :codepipeline }.never
        snapshot = @pack.map_of(@row)
        assert_equal [ ResourceMap::KIND_SERVICE ], snapshot.unread_kinds
        assert_match "AWS asked to slow down while listing App Runner services in eu-west-1", snapshot.gap_texts.last
      end

      test "a pipeline's executions are its runs, and one read by its id has each action with its error, its page and its log" do
        answer(:list_pipeline_executions, pipeline_execution_summaries: [
          { pipeline_execution_id: EXECUTION, status: "Failed", start_time: Time.utc(2026, 10, 1, 10), last_update_time: Time.utc(2026, 10, 1, 10, 9),
            source_revisions: [ { action_name: "Source", revision_id: "a1b2c3d4e5f6a7b8", revision_summary: "Fix checkout\nmore" },
                                { action_name: "Other", revision_id: "ffff" } ],
            trigger: { trigger_type: "Webhook" } },
          { pipeline_execution_id: EARLIER, status: "Succeeded", start_time: Time.utc(2026, 9, 30, 10), last_update_time: Time.utc(2026, 9, 30, 10, 8) }
        ])

        result = call(:pipeline_executions, "resource" => PIPELINE_ARN)
        runs = History.runs_of(result)
        assert_equal [ [ EXECUTION, History::FAILED, 540 ], [ EARLIER, History::SUCCEEDED, 480 ] ], runs.map { |run| [ run.id, run.status, run.seconds ] }
        assert_equal "Source a1b2c3d4e5f6, Fix checkout, started by Webhook", runs.first.detail
        assert_equal 480, result.dig(Telemetry::STRUCTURED, History::USUAL_SECONDS)

        answer(:get_pipeline_execution, pipeline_execution: { pipeline_execution_id: EXECUTION, status: "InProgress", start_time: Time.utc(2026, 10, 1, 10) })
        answer(:get_pipeline, pipeline: pipeline_definition)
        AwsApi.any_instance.stubs(:all).with { |_service, _region, called, params, *| called == :list_action_executions && params.dig(:filter, :pipeline_execution_id) == EXECUTION }
                    .returns([ [ action("Build", "Build", "Succeeded", external: "web-build:9a1b"),
                                 action("Deploy", "Deploy", "Failed", external: "d-ABCDEF123", error: { code: "JobFailed", message: "Deployment d-ABCDEF123 failed" }),
                                 action("Deploy", "Service", "InProgress"),
                                 action("Deploy", "Deploy", "Failed", started: Time.utc(2026, 10, 1, 9)) ], false ])

        listing(:list_pipelines, [ { name: "release-web" } ])
        run = History.runs_of(call(:pipeline_executions, "resource" => "release-web", "run" => EXECUTION)).sole
        assert_equal History::RUNNING, run.status
        parts = run.parts.index_by(&:name)
        assert_equal [ "Build: Build", "Deploy: Deploy", "Deploy: Service" ], run.parts.map(&:name), "the stages' order, the newest try of each action"
        assert_equal [ History::FAILED, "JobFailed: Deployment d-ABCDEF123 failed, Deploy summary" ], parts["Deploy: Deploy"].then { |part| [ part.status, part.detail ] }
        assert_equal "https://console.example/d-ABCDEF123", parts["Deploy: Deploy"].url
        assert_equal({ History::LOG_TOOL => Aws::Releases::CODEDEPLOY_DEPLOYMENTS, History::LOG_ARGUMENTS => { "resource" => "shop/web-prod", "run" => "d-ABCDEF123" } },
                     parts["Deploy: Deploy"].log)
        assert_equal Aws::Releases::SEARCH_LOGS, parts["Deploy: Service"].log[History::LOG_TOOL]
        assert_equal SERVICE_ARN, parts["Deploy: Service"].log.dig(History::LOG_ARGUMENTS, "resource")
        assert_equal "Deploy: Deploy", run.first_failed_part.name
      end

      test "a deployment group's deployments are its runs, and one by its id has its lifecycle events with the service's logs over its time" do
        answer(:list_deployments, deployments: [ "d-ABCDEF123" ])
        answer(:batch_get_deployments, deployments_info: [ deployment ])

        runs = History.runs_of(call(:codedeploy_deployments, "resource" => GROUP_ARN))
        assert_equal [ [ "d-ABCDEF123", History::FAILED, "revision 9f8e7d6c5b4a, rolled back by d-ROLLBACK12, the green tasks failed health checks, by user" ] ],
                     runs.map { |run| [ run.id, run.status, run.detail ] }
        assert_equal "https://eu-west-1.console.aws.amazon.com/codedeploy/home?region=eu-west-1#/deployments/d-ABCDEF123", runs.sole.url

        AwsApi.any_instance.stubs(:all).with { |_service, _region, called, *| called == :list_deployment_targets }.returns([ [ "prod:web" ], false ])
        answer(:batch_get_deployment_targets, deployment_targets: [ { deployment_target_type: "ECSTarget", ecs_target: { target_id: "prod:web", status: "Failed", lifecycle_events: [
          { lifecycle_event_name: "Install", status: "Succeeded", start_time: Time.utc(2026, 10, 1, 10), end_time: Time.utc(2026, 10, 1, 10, 2) },
          { lifecycle_event_name: "AfterAllowTestTraffic", status: "Failed", start_time: Time.utc(2026, 10, 1, 10, 2), end_time: Time.utc(2026, 10, 1, 10, 5),
            diagnostics: { error_code: "ScriptFailed", message: "The hook returned Failed", script_name: "CheckHealth" } }
        ] } } ])

        listing(:list_applications, [ "shop" ])
        listing(:list_deployment_groups, [ "web-prod", "other" ])
        run = History.runs_of(call(:codedeploy_deployments, "resource" => "shop/web-prod", "run" => "d-ABCDEF123")).sole
        failed = run.first_failed_part
        assert_equal [ "AfterAllowTestTraffic", "ScriptFailed, The hook returned Failed, script CheckHealth" ], [ failed.name, failed.detail ]
        assert_equal [ Aws::Releases::SEARCH_LOGS, SERVICE_ARN, "2026-10-01T10:02:00Z" ],
                     [ failed.log[History::LOG_TOOL], failed.log.dig(History::LOG_ARGUMENTS, "resource"), failed.log.dig(History::LOG_ARGUMENTS, "start") ]

        error = assert_raises(NativePack::Error) { call(:codedeploy_deployments, "resource" => "shop/other", "run" => "d-ABCDEF123") }
        assert_match "has no deployment d-ABCDEF123", error.message
      end

      test "a stack's operations are read from its events, the newest first, each with the resource that failed" do
        answer(:describe_stack_events, stack_events: [
          stack_event("e7", "UPDATE_ROLLBACK_COMPLETE", at: 18, operation: "op-2"),
          stack_event("e6", "UPDATE_FAILED", logical: "Service", type: "AWS::ECS::Service", reason: "Resource handler returned message: circuit breaker", at: 15, operation: "op-2"),
          stack_event("e5", "UPDATE_IN_PROGRESS", logical: "Service", type: "AWS::ECS::Service", at: 11, operation: "op-2"),
          stack_event("e4", "UPDATE_IN_PROGRESS", at: 10, operation: "op-2"),
          stack_event("e3", "CREATE_COMPLETE", at: 5),
          stack_event("e2", "CREATE_COMPLETE", logical: "Service", type: "AWS::ECS::Service", at: 3),
          stack_event("e1", "CREATE_IN_PROGRESS", at: 1)
        ])

        runs = History.runs_of(call(:stack_events, "resource" => STACK_ARN))
        assert_equal [ [ "op-2", "update", History::FAILED, 480 ], [ "e1", "create", History::SUCCEEDED, 240 ] ],
                     runs.map { |run| [ run.id, run.name, run.status, run.seconds ] }, "events from before operation ids join the operation their stack began"
        assert_equal "update rollback complete, Service: Resource handler returned message: circuit breaker", runs.first.detail

        run = History.runs_of(call(:stack_events, "resource" => STACK_ARN, "run" => "op-2")).sole
        assert_equal [ [ "Service (AWS::ECS::Service)", History::FAILED, "update failed, Resource handler returned message: circuit breaker" ] ],
                     run.parts.map { |part| [ part.name, part.status, part.detail ] }
      end

      test "an App Runner service's operations and an Elastic Beanstalk environment's requests are their runs, with where each one's log is" do
        answer(:list_operations, operation_summary_list: [
          { id: "op-9", type: "START_DEPLOYMENT", status: "ROLLBACK_SUCCEEDED", started_at: Time.utc(2026, 10, 1, 10), ended_at: Time.utc(2026, 10, 1, 10, 6) },
          { id: "op-8", type: "UPDATE_SERVICE", status: "SUCCEEDED", started_at: Time.utc(2026, 9, 30, 10), ended_at: Time.utc(2026, 9, 30, 10, 4) }
        ])
        answer(:describe_service, service: { service_arn: APP_ARN, service_name: "api", status: "RUNNING" })
        runs = History.runs_of(call(:app_runner_operations, "resource" => APP_ARN))
        assert_equal [ [ "start deployment", History::FAILED, "rollback succeeded" ], [ "update service", History::SUCCEEDED, nil ] ],
                     runs.map { |run| [ run.name, run.status, run.detail ] }
        part = History.runs_of(call(:app_runner_operations, "resource" => APP_ARN, "run" => "op-9")).sole.parts.sole
        assert_equal [ "/aws/apprunner/api/8fe1e10304f84fd2b0df550fe98a71fa/service" ], part.log.dig(History::LOG_ARGUMENTS, "log_groups")
        assert_equal Aws::AppPlatforms::LOGS_QUERY, part.log[History::LOG_TOOL]

        answer(:describe_environments, environments: [ { environment_arn: ENVIRONMENT_ARN, environment_name: "shop-prod", application_name: "shop", status: "Updating" } ])
        answer(:describe_events, events: [
          beanstalk_event("r-2", "Environment update is starting.", at: 20),
          beanstalk_event("r-1", "Environment update completed successfully.", at: 12, version: "v41"),
          beanstalk_event("r-1", "Deploying new version to instance(s).", at: 11),
          beanstalk_event("r-1", "Environment update is starting.", at: 10),
          beanstalk_event("r-0", "Failed to deploy application.", at: 5, severity: "ERROR"),
          beanstalk_event("r-0", "Environment update is starting.", at: 1)
        ])
        listing(:describe_environments, [ { environment_arn: ENVIRONMENT_ARN, environment_name: "shop-prod", application_name: "shop", status: "Updating" } ])
        runs = History.runs_of(call(:beanstalk_events, "resource" => "shop-prod")).index_by(&:id)
        assert_equal [ "Environment update", History::RUNNING ], runs["r-2"].then { |run| [ run.name, run.status ] }, "the newest request of a busy environment is still going"
        assert_equal [ History::SUCCEEDED, "version v41" ], runs["r-1"].then { |run| [ run.status, run.detail ] }
        assert_equal [ History::FAILED, "Failed to deploy application." ], runs["r-0"].then { |run| [ run.status, run.detail ] }

        answer(:describe_configuration_settings, configuration_settings: [ { option_settings: [ { namespace: "aws:elasticbeanstalk:cloudwatch:logs", option_name: "StreamLogs", value: "true" } ] } ])
        run = History.runs_of(call(:beanstalk_events, "resource" => ENVIRONMENT_ARN, "run" => "r-0")).sole
        assert_equal [ "/aws/elasticbeanstalk/shop-prod/var/log/eb-engine.log" ], run.first_failed_part.log.dig(History::LOG_ARGUMENTS, "log_groups")
      end

      test "an App Runner service's deploying operations and an environment's versioned requests are its deploys, the one serving by the environment's version" do
        answer(:list_operations, operation_summary_list: [
          { id: "op-10", type: "PAUSE_SERVICE", status: "SUCCEEDED", started_at: Time.utc(2026, 10, 2, 10), ended_at: Time.utc(2026, 10, 2, 10, 1) },
          { id: "op-9", type: "START_DEPLOYMENT", status: "ROLLBACK_SUCCEEDED", started_at: Time.utc(2026, 10, 1, 10), ended_at: Time.utc(2026, 10, 1, 10, 6) },
          { id: "op-8", type: "UPDATE_SERVICE", status: "SUCCEEDED", started_at: Time.utc(2026, 9, 30, 10), ended_at: Time.utc(2026, 9, 30, 10, 4) }
        ])
        answer(:describe_service, service: { service_arn: APP_ARN, service_name: "api", status: "RUNNING" })
        deploys = Capabilities::Deploys.deploys_of(call(:app_runner_operations, "resource" => APP_ARN))
        assert_equal [ [ "op-9", History::FAILED, nil, Time.utc(2026, 10, 1, 10, 6) ], [ "op-8", History::SUCCEEDED, nil, Time.utc(2026, 9, 30, 10, 4) ] ],
                     deploys.map { |deploy| [ deploy.id, deploy.status, deploy.live, deploy.finished_at ] }

        ready = { environment_arn: ENVIRONMENT_ARN, environment_name: "shop-prod", application_name: "shop", status: "Ready", version_label: "v42" }
        answer(:describe_environments, environments: [ ready ])
        answer(:describe_events, events: [
          beanstalk_event("r-4", "Environment update completed successfully.", at: 40),
          beanstalk_event("r-4", "Environment update is starting.", at: 39),
          beanstalk_event("r-3", "Environment update completed successfully.", at: 31, version: "v42"),
          beanstalk_event("r-3", "Environment update is starting.", at: 30),
          beanstalk_event("r-2", "Environment update completed successfully.", at: 21, version: "v41"),
          beanstalk_event("r-2", "Environment update is starting.", at: 20),
          beanstalk_event("r-1", "Environment update completed successfully.", at: 11, version: "v42"),
          beanstalk_event("r-1", "Environment update is starting.", at: 10)
        ])
        result = call(:beanstalk_events, "resource" => ENVIRONMENT_ARN)
        assert_equal [ [ "r-3", "v42", History::SUCCEEDED, true ], [ "r-2", "v41", History::SUCCEEDED, false ], [ "r-1", "v42", History::SUCCEEDED, false ] ],
                     Capabilities::Deploys.deploys_of(result).map { |deploy| [ deploy.id, deploy.version, deploy.status, deploy.live ] }
        assert_equal [ Time.utc(2026, 10, 1, 10, 30), Time.utc(2026, 10, 1, 10, 31) ], Capabilities::Deploys.deploys_of(result).first.then { |deploy| [ deploy.started_at, deploy.finished_at ] }
        answer(:describe_configuration_settings, configuration_settings: [])
        assert_equal [ "r-2" ], Capabilities::Deploys.deploys_of(call(:beanstalk_events, "resource" => ENVIRONMENT_ARN, "run" => "r-2")).map(&:id)

        answer(:describe_environments, environments: [ ready.merge(status: "Updating") ])
        assert_equal [ nil, nil, nil ], Capabilities::Deploys.deploys_of(call(:beanstalk_events, "resource" => ENVIRONMENT_ARN)).map(&:live), "a busy environment does not say which serves"
      end

      test "an ECS deployment still going stops and rolls back, and one already over is refused" do
        answer(:describe_service_deployments, service_deployments: [ { status: "IN_PROGRESS" } ])
        AwsApi.any_instance.expects(:call).with(:ecs, REGION, :stop_service_deployment,
                                                 service_deployment_arn: "arn:aws:ecs:#{REGION}:#{ACCOUNT}:service-deployment/prod/web/NCWGC2ZR-taawPAYrIaU5", stop_type: "ROLLBACK")
        assert_match "is stopping and rolling web back", text(:stop_service_deployment, "resource" => SERVICE_ARN, "deployment" => "NCWGC2ZR-taawPAYrIaU5")

        answer(:describe_service_deployments, service_deployments: [ { status: "SUCCESSFUL" } ])
        assert_match "is successful, so there is nothing to stop", refusal(:stop_service_deployment, "resource" => SERVICE_ARN, "deployment" => "NCWGC2ZR-taawPAYrIaU5")
        assert_match "mode must be rollback or abort", refusal(:stop_service_deployment, "resource" => SERVICE_ARN, "deployment" => "NCWGC2ZR-taawPAYrIaU5", "mode" => "later")
      end

      test "a pipeline execution stops only while it runs, and a stage rolls back to an earlier execution that succeeded in it" do
        answer(:get_pipeline_execution, pipeline_execution: { pipeline_execution_id: EXECUTION, status: "InProgress" })
        AwsApi.any_instance.expects(:call).with(:codepipeline, REGION, :stop_pipeline_execution,
                                                 { pipeline_name: "release-web", pipeline_execution_id: EXECUTION, abandon: false, reason: "bad build" })
        assert_match "Its actions in progress finish first", text(:stop_pipeline_execution, "resource" => PIPELINE_ARN, "execution" => EXECUTION, "reason" => "bad build")

        answer(:get_pipeline_execution, pipeline_execution: { pipeline_execution_id: EARLIER, status: "Succeeded" })
        answer(:get_pipeline, pipeline: pipeline_definition)
        assert_match "is succeeded, so there is nothing to stop", refusal(:stop_pipeline_execution, "resource" => PIPELINE_ARN, "execution" => EARLIER)
        assert_match "Say which stage of release-web to roll back. Deploy and Approve deploy", refusal(:rollback_pipeline_stage, "resource" => PIPELINE_ARN, "to" => EARLIER)

        AwsApi.any_instance.expects(:call).with(:codepipeline, REGION, :rollback_stage, pipeline_name: "release-web", stage_name: "Deploy", target_pipeline_execution_id: EARLIER)
        assert_match "Stage Deploy of release-web is rolling back", text(:rollback_pipeline_stage, "resource" => PIPELINE_ARN, "stage" => "Deploy", "to" => EARLIER)
      end

      test "a CodeDeploy deployment still going stops and rolls back, and a stack update is cancelled only while it is the one going" do
        answer(:batch_get_deployments, deployments_info: [ deployment(status: "InProgress") ])
        AwsApi.any_instance.expects(:call).with(:codedeploy, REGION, :stop_deployment, deployment_id: "d-ABCDEF123", auto_rollback_enabled: true)
        assert_match "rolling back what it changed", text(:stop_codedeploy_deployment, "resource" => GROUP_ARN, "deployment" => "d-ABCDEF123")

        answer(:describe_stacks, stacks: [ { stack_id: STACK_ARN, stack_name: "shop-infra", stack_status: "UPDATE_COMPLETE" } ])
        assert_match "is update complete. Only an update still going can be cancelled", refusal(:cancel_stack_update, "resource" => STACK_ARN)

        answer(:describe_stacks, stacks: [ { stack_id: STACK_ARN, stack_name: "shop-infra", stack_status: "UPDATE_IN_PROGRESS" } ])
        answer(:describe_stack_events, stack_events: [ stack_event("e9", "UPDATE_IN_PROGRESS", at: 30, operation: "op-3") ])
        assert_match "is not the update going now (op-3)", refusal(:cancel_stack_update, "resource" => STACK_ARN, "operation" => "op-2")
        AwsApi.any_instance.expects(:call).with(:cloudformation, REGION, :cancel_update_stack, stack_name: STACK_ARN)
        assert_match "rolls the stack back", text(:cancel_stack_update, "resource" => STACK_ARN, "operation" => "op-3")
      end

      test "the main tools say where an App Runner service or a release is read rather than looking for it" do
        assert_match "is an App Runner service. describe_app reads how it stands, and app_runner_operations its deploys", refusal(:describe_resource, "resource" => APP_ARN)
        assert_match "releases code rather than running it", refusal(:describe_resource, "resource" => PIPELINE_ARN)
      end

      test "an event's re-read reads one pipeline or environment, and one AWS no longer has is gone" do
        answer(:get_pipeline, pipeline: pipeline_definition)
        answer(:list_pipeline_executions, pipeline_execution_summaries: [ { pipeline_execution_id: EXECUTION, status: "Succeeded" } ])
        refreshed = @pack.map_refresh(@row, ResourceMap::Scope.new(account: ACCOUNT, kind: ResourceMap::KIND_PIPELINE, external_id: PIPELINE_ARN))
        assert_equal [ [ PIPELINE_ARN, "succeeded" ] ], refreshed.resources.map { |each| [ each.external_id, each.status ] }

        answer(:get_pipeline, raises: [ AwsApi::NotFound, "AWS answered PipelineNotFoundException: gone" ])
        gone = @pack.map_refresh(@row, ResourceMap::Scope.new(account: ACCOUNT, kind: ResourceMap::KIND_PIPELINE, external_id: PIPELINE_ARN))
        assert_equal [ [ "aws", ACCOUNT, ResourceMap::KIND_PIPELINE, PIPELINE_ARN ] ], gone.gone

        answer(:describe_environments, environments: [])
        gone = @pack.map_refresh(@row, ResourceMap::Scope.new(account: ACCOUNT, kind: ResourceMap::KIND_SERVICE, external_id: ENVIRONMENT_ARN))
        assert_equal [ [ "aws", ACCOUNT, ResourceMap::KIND_SERVICE, ENVIRONMENT_ARN ] ], gone.gone
      end

      test "the general read reaches App Runner and Elastic Beanstalk, with runtime variables named and environment properties hidden" do
        assert_includes AwsApi::SERVICES, "apprunner"
        assert_includes AwsApi::SERVICES, "elasticbeanstalk"
        hidden = ReadGuards::Aws.hidden(
          service: { source_configuration: { image_repository: { image_configuration: { runtime_environment_variables: { "DATABASE_URL" => "postgres://u:p@h/d" } } } } },
          configuration_settings: [ { option_settings: [ { namespace: "aws:elasticbeanstalk:application:environment", option_name: "API_KEY", value: "sk_live_1" },
                                                         { namespace: "aws:autoscaling:asg", option_name: "MaxSize", value: "4" } ] } ]
        )
        assert_not_includes hidden.to_s, "postgres://u:p@h/d"
        assert_not_includes hidden.to_s, "sk_live_1"
        assert_includes hidden.to_s, "DATABASE_URL"
        assert_equal "4", hidden.dig(:configuration_settings, 0, :option_settings, 1, :value)
      end

      private

      def call(tool, arguments) = @pack.call(tool.to_s, environment_row: @row, arguments: arguments)

      def text(tool, arguments) = call(tool, arguments)["content"].sole["text"]

      def refusal(tool, arguments)
        assert_raises(NativePack::Error) { Aws.new(@integration).call(tool.to_s, environment_row: @row, arguments: arguments) }.message
      end

      def answer(operation, raises: nil, **returned)
        stub = AwsApi.any_instance.stubs(:call).with { |_service, _region, called, *| called == operation }
        raises ? stub.raises(*raises) : stub.returns(returned)
      end

      def listing(operation, rows, service: nil)
        AwsApi.any_instance.stubs(:all).with { |at_service, _region, called, *| called == operation && (service.nil? || at_service == service) }.returns([ rows, false ])
      end

      def pipeline_definition
        deploy = ->(name, provider, configuration) { { name: name, action_type_id: { category: "Deploy", owner: "AWS", provider: provider, version: "1" }, configuration: configuration } }
        { name: "release-web", pipeline_type: "V2", stages: [
          { name: "Source", actions: [ { name: "Source", action_type_id: { category: "Source", provider: "CodeStarSourceConnection" } } ] },
          { name: "Build", actions: [ { name: "Build", action_type_id: { category: "Build", provider: "CodeBuild" }, configuration: { "ProjectName" => "web-build" } } ] },
          { name: "Deploy", actions: [ deploy.call("Deploy", "CodeDeployToECS", { "ApplicationName" => "shop", "DeploymentGroupName" => "web-prod" }),
                                       deploy.call("Service", "ECS", { "ClusterName" => "prod", "ServiceName" => "web" }) ] },
          { name: "Approve", actions: [ deploy.call("Infra", "CloudFormation", { "StackName" => "shop-infra" }),
                                        deploy.call("Beanstalk", "ElasticBeanstalk", { "ApplicationName" => "shop", "EnvironmentName" => "shop-prod" }) ] }
        ] }
      end

      def action(stage, name, status, external: nil, error: nil, started: Time.utc(2026, 10, 1, 10, 1))
        result = { external_execution_id: external, external_execution_summary: "#{name} summary", external_execution_url: ("https://console.example/#{external}" if external),
                   error_details: error }.compact
        { pipeline_execution_id: EXECUTION, action_execution_id: "#{stage}-#{name}-#{started.to_i}", stage_name: stage, action_name: name, status: status,
          start_time: started, last_update_time: started + 120, output: { execution_result: result } }
      end

      def deployment(status: "Failed")
        { deployment_id: "d-ABCDEF123", application_name: "shop", deployment_group_name: "web-prod", status: status, creator: "user",
          create_time: Time.utc(2026, 10, 1, 10), start_time: Time.utc(2026, 10, 1, 10), complete_time: Time.utc(2026, 10, 1, 10, 7),
          revision: { revision_type: "AppSpecContent", app_spec_content: { sha_256: "9f8e7d6c5b4a3b2c1d0e" } },
          rollback_info: { rollback_deployment_id: "d-ROLLBACK12" }, error_information: { code: "HEALTH_CONSTRAINTS", message: "the green tasks failed health checks" } }
      end

      def stack_event(id, status, at:, logical: "shop-infra", type: Aws::Releases::STACK_TYPE, reason: nil, operation: nil)
        { stack_id: STACK_ARN, event_id: id, stack_name: "shop-infra", logical_resource_id: logical, resource_type: type, resource_status: status,
          resource_status_reason: reason, timestamp: Time.utc(2026, 10, 1, 10, at), operation_id: operation }.compact
      end

      def beanstalk_event(request, message, at:, severity: "INFO", version: nil)
        { request_id: request, message: message, severity: severity, event_date: Time.utc(2026, 10, 1, 10, at), environment_name: "shop-prod",
          application_name: "shop", version_label: version }.compact
      end
    end
  end
end
