require "test_helper"

module Integrations
  module Packs
    # One ECS deployment or CodeBuild build read by its id with its parts, CodeBuild's builds as run history, and a build's
    # own log. Answers follow the ECS API reference (ServiceDeployment) and the CodeBuild API reference (Build, BuildPhase,
    # LogsLocation), in the SDK's shapes.
    class AwsRunsTest < ActiveSupport::TestCase
      ACCOUNT = "123456789012".freeze
      SERVICE_ARN = "arn:aws:ecs:eu-west-1:#{ACCOUNT}:service/prod/web".freeze
      DEPLOYMENT_ARN = "arn:aws:ecs:eu-west-1:#{ACCOUNT}:service-deployment/prod/web/NCWGC2ZR-taawPAYrIaU5".freeze
      TASK_DEFINITION = "arn:aws:ecs:eu-west-1:#{ACCOUNT}:task-definition/web:42".freeze
      PROJECT_ARN = "arn:aws:codebuild:eu-west-1:#{ACCOUNT}:project/web-build".freeze
      BUILD_ID = "web-build:0f6c1d2e-8b7a-4c55-9a1e-2f3b4c5d6e7f".freeze
      CONSOLE = "https://eu-west-1.console.aws.amazon.com".freeze

      setup do
        @integration = Integration.create!(workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_NATIVE, provider: "aws", name: "AWS")
        @row = @integration.integration_environments.create!
        Aws.store_credentials!(@row, Aws::ACCESS_KEY_ID => "AKIAEXAMPLE", Aws::SECRET_ACCESS_KEY => "secret")
        @row.store_fields!(Aws::REGIONS => %w[eu-west-1])
        @pack = Aws.new(@integration)
        AwsApi.any_instance.stubs(:identity).returns(account: ACCOUNT)
        # A project named by its name is found by listing what the connection reaches.
        AwsApi.any_instance.stubs(:all).returns([ [], false ])
        AwsApi.any_instance.stubs(:all).with { |service, _region, operation, *| service == :codebuild && operation == :list_projects }.returns([ [ "web-build" ], false ])
        AwsApi.any_instance.stubs(:call).with(:codebuild, "eu-west-1", :batch_get_projects, names: [ "web-build" ]).returns(projects: [ { name: "web-build", arn: PROJECT_ARN } ])
      end

      test "an ECS deployment read by its id is found by its own ARN, with its rollout and rollback as parts, why tasks stopped and its page" do
        AwsApi.any_instance.expects(:call).with(:ecs, "eu-west-1", :describe_service_deployments, service_deployment_arns: [ DEPLOYMENT_ARN ]).returns(
          service_deployments: [ {
            service_deployment_arn: DEPLOYMENT_ARN, status: "ROLLBACK_SUCCESSFUL", status_reason: "Service deployment rolled back because the circuit breaker threshold was exceeded.",
            created_at: Time.utc(2026, 10, 1, 10), started_at: Time.utc(2026, 10, 1, 10), finished_at: Time.utc(2026, 10, 1, 10, 12),
            target_service_revision: { arn: "rev-42", requested_task_count: 2, running_task_count: 0 }, lifecycle_stage: "CLEAN_UP",
            rollback: { reason: "Circuit breaker tripped", started_at: Time.utc(2026, 10, 1, 10, 8), service_revision_arn: "rev-41" },
            deployment_circuit_breaker: { status: "TRIGGERED", failure_count: 10, threshold: 10 }
          } ]
        )
        answer(:describe_service_revisions, service_revisions: [ { service_revision_arn: "rev-42", task_definition: TASK_DEFINITION } ])
        answer(:list_tasks, task_arns: [ "task-1", "task-2" ])
        answer(:describe_tasks, tasks: [
          { task_arn: "task-1", task_definition_arn: TASK_DEFINITION, stop_code: "TaskFailedToStart",
            stopped_reason: "CannotPullContainerError: pull image manifest has been retried 5 time(s)", containers: [ { name: "app", reason: "CannotPullContainerError" } ] },
          { task_arn: "task-2", task_definition_arn: TASK_DEFINITION.sub(":42", ":41"), stop_code: "ServiceSchedulerInitiated", stopped_reason: "Scaling activity" }
        ])

        result = call(:list_deployments, "resource" => SERVICE_ARN, "run" => "NCWGC2ZR-taawPAYrIaU5")
        run = Capabilities::History.runs_of(result).sole
        rollout, rollback = run.parts

        assert_equal [ "NCWGC2ZR-taawPAYrIaU5", "failed", 720 ], [ run.id, run.status, run.seconds ]
        assert_equal "#{CONSOLE}/ecs/v2/clusters/prod/services/web/deployments?region=eu-west-1", run.url
        assert_equal [ "rollout of web:42", "failed" ], [ rollout.name, rollout.status ]
        assert_match "0 of 2 tasks running, circuit breaker triggered, 10 of 10 failed tasks", rollout.detail
        assert_match "tasks stopped: TaskFailedToStart: CannotPullContainerError", rollout.detail
        assert_no_match "Scaling activity", rollout.detail, "a task of another revision is not this deployment's"
        assert_equal({ "tool" => "search_logs", "arguments" => { "resource" => SERVICE_ARN, "start" => "2026-10-01T10:00:00Z", "end" => "2026-10-01T10:12:00Z" } }, rollout.log)
        assert_equal [ "rollback", "succeeded", "Circuit breaker tripped" ], [ rollback.name, rollback.status, rollback.detail ]
        assert_equal rollout, run.first_failed_part
        assert_match "#{CONSOLE}/ecs/v2/clusters/prod/services/web/deployments?region=eu-west-1", result["content"].sole["text"]
      end

      test "a deployment still rolling out says the stage it is at, and one ECS does not have is said" do
        answer(:describe_service_deployments, service_deployments: [ {
          service_deployment_arn: DEPLOYMENT_ARN, status: "IN_PROGRESS", started_at: Time.utc(2026, 10, 1, 10),
          target_service_revision: { arn: "rev-42", requested_task_count: 2, running_task_count: 1 }, lifecycle_stage: "BAKE_TIME"
        } ])
        answer(:describe_service_revisions, service_revisions: [ { service_revision_arn: "rev-42", task_definition: TASK_DEFINITION } ])

        rollout = Capabilities::History.runs_of(call(:list_deployments, "resource" => SERVICE_ARN, "run" => DEPLOYMENT_ARN)).sole.parts.sole

        assert_equal [ "running", "at bake time, 1 of 2 tasks running" ], [ rollout.status, rollout.detail ]
        assert_equal({ "resource" => SERVICE_ARN, "start" => "2026-10-01T10:00:00Z" }, rollout.log["arguments"])

        answer(:describe_service_deployments, service_deployments: [], failures: [ { arn: DEPLOYMENT_ARN, reason: "MISSING" } ])
        assert_match "ECS has no deployment NCWGC2ZR-taawPAYrIaU5 of web", refusal(:list_deployments, "resource" => SERVICE_ARN, "run" => "NCWGC2ZR-taawPAYrIaU5")
        assert_match "run must be the deployment's id", refusal(:list_deployments, "resource" => SERVICE_ARN, "run" => "../x y")
      end

      test "a CodeBuild project's builds are its run history, newest first, each linking to its own page" do
        AwsApi.any_instance.expects(:call).with(:codebuild, "eu-west-1", :list_builds_for_project, project_name: "web-build", sort_order: "DESCENDING")
              .returns(ids: [ BUILD_ID, "web-build:older" ])
        AwsApi.any_instance.expects(:call).with(:codebuild, "eu-west-1", :batch_get_builds, ids: [ BUILD_ID, "web-build:older" ]).returns(builds: [
          build(id: "web-build:older", build_number: 11, build_status: "SUCCEEDED", start_time: Time.utc(2026, 10, 1, 9), end_time: Time.utc(2026, 10, 1, 9, 6)),
          build
        ])

        result = call(:list_builds, "resource" => "arn:aws:codebuild:eu-west-1:#{ACCOUNT}:project/web-build")
        runs = Capabilities::History.runs_of(result)

        assert_equal [ [ BUILD_ID, "12", "failed", 300 ], [ "web-build:older", "11", "succeeded", 360 ] ], runs.map { |run| [ run.id, run.number, run.status, run.seconds ] }
        assert_equal "#{CONSOLE}/codesuite/codebuild/#{ACCOUNT}/projects/web-build/build/web-build%3A0f6c1d2e-8b7a-4c55-9a1e-2f3b4c5d6e7f?region=eu-west-1", runs.first.url
        assert_equal "at 9f1c2d3e4f5a, started by GitHub-Hookshot/1a2b3c", runs.first.detail
        assert_nil runs.first.parts, "a listed build is not read phase by phase"
        assert_match "2 recent runs of the builds of web-build, newest first. Finished ones usually take 6 minutes.", result["content"].sole["text"]
        assert_equal "#{CONSOLE}/codesuite/codebuild/#{ACCOUNT}/projects/web-build/history?region=eu-west-1", Capabilities::RunHistory.link_of(result).url
      end

      test "one build read by its id, ARN or number has its phases as parts, each failed one with CodeBuild's words and its log the build's" do
        AwsApi.any_instance.stubs(:call).with(:codebuild, "eu-west-1", :batch_get_builds, ids: [ BUILD_ID ]).returns(builds: [ build ])

        [ BUILD_ID, "0f6c1d2e-8b7a-4c55-9a1e-2f3b4c5d6e7f", "arn:aws:codebuild:eu-west-1:#{ACCOUNT}:build/#{BUILD_ID}" ].each do |asked|
          run = Capabilities::History.runs_of(call(:list_builds, "resource" => "web-build", "run" => asked)).sole

          assert_equal [ "submitted", "provisioning", "build" ], run.parts.map(&:name), asked
          failed = run.first_failed_part
          assert_equal [ "build", "failed", 120 ], [ failed.name, failed.status, failed.seconds ]
          assert_equal "COMMAND_EXECUTION_ERROR: Error while executing command: npm test. Reason: exit status 1", failed.detail
          assert_equal({ "tool" => "build_log", "arguments" => { "resource" => PROJECT_ARN, "build" => BUILD_ID } }, failed.log)
        end

        AwsApi.any_instance.stubs(:call).with(:codebuild, "eu-west-1", :list_builds_for_project, project_name: "web-build", sort_order: "DESCENDING").returns(ids: [ BUILD_ID ])
        assert_equal BUILD_ID, Capabilities::History.runs_of(call(:list_builds, "resource" => "web-build", "run" => "#12")).sole.id

        AwsApi.any_instance.stubs(:call).with(:codebuild, "eu-west-1", :batch_get_builds, ids: [ "web-build:gone" ]).returns(builds: [], builds_not_found: [ "web-build:gone" ])
        assert_match "CodeBuild has no build web-build:gone of web-build", refusal(:list_builds, "resource" => "web-build", "run" => "web-build:gone")
        assert_match "is a build of other, not of web-build", refusal(:list_builds, "resource" => "web-build", "run" => "other:1234")
        assert_match "only CodeBuild projects have builds", refusal(:list_builds, "resource" => SERVICE_ARN)
      end

      test "a build's log is the end of its own CloudWatch Logs stream, filtered as asked, linking to the log AWS names" do
        AwsApi.any_instance.stubs(:call).with(:codebuild, "eu-west-1", :batch_get_builds, ids: [ BUILD_ID ]).returns(builds: [ build ])
        AwsApi.any_instance.expects(:call).with(:logs, "eu-west-1", :get_log_events, log_group_name: "/aws/codebuild/web-build",
                                                log_stream_name: "0f6c1d2e-8b7a-4c55-9a1e-2f3b4c5d6e7f", start_from_head: false, limit: Aws::LOG_EVENTS)
              .returns(events: [ { timestamp: 1, message: "[Container] Running command npm test\n" }, { timestamp: 2, message: "FAIL test/checkout.test.js\n" },
                                 { timestamp: 3, message: "npm ERR! Test failed.\n" } ])

        result = call(:build_log, "resource" => "web-build", "build" => BUILD_ID, "regex" => "FAIL|ERR")
        text = result["content"].sole["text"]

        assert_match "Build 12 (#{BUILD_ID}) of web-build, failed, started 2026-10-01T10:00:00Z, ended 2026-10-01T10:05:00Z.", text
        assert_match "Its log, 2 lines:\nFAIL test/checkout.test.js\nnpm ERR! Test failed.", text
        assert_match "https://console.aws.amazon.com/cloudwatch/home?region=eu-west-1#logEvent:group=/aws/codebuild/web-build", text
      end

      test "a build that keeps its log only in S3, or has not written one yet, says so" do
        s3_only = build(logs: { cloud_watch_logs: { status: "DISABLED" }, s3_logs: { status: "ENABLED", location: "logs-bucket/web" } })
        AwsApi.any_instance.stubs(:call).with(:codebuild, "eu-west-1", :batch_get_builds, ids: [ BUILD_ID ]).returns(builds: [ s3_only ])
        assert_match "keeps no log in CloudWatch Logs", refusal(:build_log, "resource" => "web-build", "build" => BUILD_ID)

        AwsApi.any_instance.stubs(:call).with(:codebuild, "eu-west-1", :batch_get_builds, ids: [ BUILD_ID ])
              .returns(builds: [ build(build_status: "IN_PROGRESS", end_time: nil, logs: { cloud_watch_logs: { status: "ENABLED" } }) ])
        assert_match "has written no log to CloudWatch Logs yet", refusal(:build_log, "resource" => "web-build", "build" => BUILD_ID)
      end

      test "a project is described with its source, environment and latest builds, its variables only named and no address credential shown" do
        AwsApi.any_instance.stubs(:call).with(:codebuild, "eu-west-1", :batch_get_projects, names: [ PROJECT_ARN ]).returns(projects: [ {
          name: "web-build", arn: PROJECT_ARN, source: { type: "GITHUB", location: "https://user:hunter2@github.com/acme/web.git" }, timeout_in_minutes: 60,
          environment: { type: "LINUX_CONTAINER", image: "aws/codebuild/standard:7.0", compute_type: "BUILD_GENERAL1_SMALL",
                         environment_variables: [ { name: "NPM_TOKEN", value: "npm_secret", type: "PLAINTEXT" } ] },
          logs_config: { cloud_watch_logs: { status: "ENABLED" } }
        } ])
        AwsApi.any_instance.stubs(:call).with(:codebuild, "eu-west-1", :list_builds_for_project, project_name: "web-build", sort_order: "DESCENDING").returns(ids: [ BUILD_ID ])
        AwsApi.any_instance.stubs(:call).with(:codebuild, "eu-west-1", :batch_get_builds, ids: [ BUILD_ID ]).returns(builds: [ build ])

        text = call(:describe_resource, "resource" => "web-build")["content"].sole["text"]

        assert_match "web-build, CodeBuild project, eu-west-1", text
        assert_match "Source: GITHUB https://github.com/acme/web.git", text
        assert_match "Environment variables: NPM_TOKEN", text
        assert_match "Latest builds, newest first:\n- #12 web-build build: failed", text
        assert_no_match "npm_secret", text
        assert_no_match "hunter2", text
        assert_match "no CloudWatch metrics", refusal(:cloudwatch_metrics, "resource" => "web-build")
        assert_match "Read one with build_log", refusal(:search_logs, "resource" => "web-build")
      end

      test "a project changed or removed is read again on its own, and gone when CodeBuild no longer has it" do
        scope = ResourceMap::Scope.new(account: ACCOUNT, kind: ResourceMap::KIND_BUILD_SERVICE, external_id: PROJECT_ARN)
        AwsApi.any_instance.stubs(:call).with(:codebuild, "eu-west-1", :batch_get_projects, names: [ PROJECT_ARN ])
              .returns(projects: [ { name: "web-build", arn: PROJECT_ARN, tags: [ { key: "team", value: "web" } ] } ])
        assert_equal [ [ "web-build", { "region" => "eu-west-1", ResourceMap::TAGS => { "team" => "web" } } ] ],
                     @pack.map_refresh(@row, scope).resources.map { |resource| [ resource.name, resource.details ] }

        AwsApi.any_instance.stubs(:call).with(:codebuild, "eu-west-1", :batch_get_projects, names: [ PROJECT_ARN ]).returns(projects: [], projects_not_found: [ PROJECT_ARN ])
        assert_equal [ [ "aws", ACCOUNT, ResourceMap::KIND_BUILD_SERVICE, PROJECT_ARN ] ], @pack.map_refresh(@row, scope).gone
      end

      test "a general read of one run links to that run's own page" do
        AwsApi.any_instance.stubs(:call).returns({})
        links = {
          { "service" => "codebuild", "operation" => "BatchGetBuilds", "params" => { "ids" => [ BUILD_ID ] } } =>
            "#{CONSOLE}/codesuite/codebuild/#{ACCOUNT}/projects/web-build/build/web-build%3A0f6c1d2e-8b7a-4c55-9a1e-2f3b4c5d6e7f?region=eu-west-1",
          { "service" => "ecs", "operation" => "DescribeServiceDeployments", "params" => { "serviceDeploymentArns" => [ DEPLOYMENT_ARN ] } } =>
            "#{CONSOLE}/ecs/v2/clusters/prod/services/web/deployments?region=eu-west-1",
          { "service" => "codepipeline", "operation" => "GetPipelineExecution", "params" => { "pipelineName" => "release", "pipelineExecutionId" => "e-1" } } =>
            "#{CONSOLE}/codesuite/codepipeline/pipelines/release/executions/e-1/timeline?region=eu-west-1",
          { "service" => "codedeploy", "operation" => "GetDeployment", "params" => { "deploymentId" => "d-ABC123" } } =>
            "#{CONSOLE}/codesuite/codedeploy/deployments/d-ABC123?region=eu-west-1",
          { "service" => "codebuild", "operation" => "BatchGetBuilds", "params" => { "ids" => [ BUILD_ID, "web-build:x" ] } } =>
            "#{CONSOLE}/codesuite/codebuild/projects?region=eu-west-1"
        }
        links.each do |arguments, url|
          assert_includes call(ApiReads::TOOL, arguments)["content"].sole["text"], url, arguments.to_s
        end
      end

      private

      def call(tool, arguments) = @pack.call(tool.to_s, environment_row: @row, arguments: arguments)

      def refusal(tool, arguments)
        assert_raises(NativePack::Error) { Aws.new(@integration).call(tool.to_s, environment_row: @row, arguments: arguments) }.message
      end

      def answer(operation, **returned)
        AwsApi.any_instance.stubs(:call).with { |_service, _region, called, *| called == operation }.returns(returned)
      end

      def build(**overrides)
        {
          id: BUILD_ID, arn: "arn:aws:codebuild:eu-west-1:#{ACCOUNT}:build/#{BUILD_ID}", build_number: 12, project_name: "web-build",
          build_status: "FAILED", current_phase: "COMPLETED", start_time: Time.utc(2026, 10, 1, 10), end_time: Time.utc(2026, 10, 1, 10, 5),
          resolved_source_version: "9f1c2d3e4f5a6b7c", initiator: "GitHub-Hookshot/1a2b3c",
          phases: [
            { phase_type: "SUBMITTED", phase_status: "SUCCEEDED", start_time: Time.utc(2026, 10, 1, 10), end_time: Time.utc(2026, 10, 1, 10, 0, 1), duration_in_seconds: 1 },
            { phase_type: "PROVISIONING", phase_status: "SUCCEEDED", start_time: Time.utc(2026, 10, 1, 10, 0, 1), end_time: Time.utc(2026, 10, 1, 10, 3) },
            { phase_type: "BUILD", phase_status: "FAILED", start_time: Time.utc(2026, 10, 1, 10, 3), end_time: Time.utc(2026, 10, 1, 10, 5),
              contexts: [ { status_code: "COMMAND_EXECUTION_ERROR", message: "Error while executing command: npm test. Reason: exit status 1" } ] },
            { phase_type: "COMPLETED", start_time: Time.utc(2026, 10, 1, 10, 5) }
          ],
          logs: { group_name: "/aws/codebuild/web-build", stream_name: "0f6c1d2e-8b7a-4c55-9a1e-2f3b4c5d6e7f",
                  deep_link: "https://console.aws.amazon.com/cloudwatch/home?region=eu-west-1#logEvent:group=/aws/codebuild/web-build;stream=0f6c1d2e-8b7a-4c55-9a1e-2f3b4c5d6e7f",
                  cloud_watch_logs: { status: "ENABLED" } }
        }.merge(overrides)
      end
    end
  end
end
