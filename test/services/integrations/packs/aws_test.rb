require "test_helper"

module Integrations
  module Packs
    class AwsTest < ActiveSupport::TestCase
      ACCOUNT = "123456789012".freeze
      CLUSTER_ARN = "arn:aws:ecs:eu-west-1:#{ACCOUNT}:cluster/prod".freeze
      SERVICE_ARN = "arn:aws:ecs:eu-west-1:#{ACCOUNT}:service/prod/web".freeze
      FUNCTION_ARN = "arn:aws:lambda:eu-west-1:#{ACCOUNT}:function:checkout".freeze
      DATABASE_ARN = "arn:aws:rds:eu-west-1:#{ACCOUNT}:db:orders".freeze
      INSTANCE_ARN = "arn:aws:ec2:eu-west-1:#{ACCOUNT}:instance/i-0abc".freeze
      TASK_DEFINITION = "arn:aws:ecs:eu-west-1:#{ACCOUNT}:task-definition/web:42".freeze

      setup do
        @workspace = workspaces(:slack_workspace_one)
        @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "aws", name: "AWS")
        @row = @integration.integration_environments.create!
        Aws.store_credentials!(@row, Aws::ACCESS_KEY_ID => " AKIAEXAMPLE ", Aws::SECRET_ACCESS_KEY => " secret ")
        @row.store_fields!(Aws::REGIONS => %w[eu-west-1 us-east-1])
        @pack = Aws.new(@integration)
        AwsApi.any_instance.stubs(:identity).returns(account: ACCOUNT, arn: "arn:aws:iam::#{ACCOUNT}:user/firefight")
        answer(:describe_services, services: [ service ])
        answer(:describe_task_definition, task_definition: task_definition)
      end

      test "the keys are stored trimmed and the regions are a connect field, and only the three changes are not read only" do
        assert_equal [ "AKIAEXAMPLE", "secret", nil ], @row.reload.credentials_hash.values_at(Aws::ACCESS_KEY_ID, Aws::SECRET_ACCESS_KEY, Aws::REGIONS)
        regions = IntegrationProvider.find(Aws::PROVIDER_KEY).connect_fields.find { |field| field.key == Aws::REGIONS }
        assert regions.multiple
        assert_equal [ "us-east-1", "US East (N. Virginia)" ], regions.options.first.to_h.values_at(:value, :label)
        assert_nil regions.refusal(%w[eu-west-1 ap-southeast-7])
        assert_match "Regions can only be", regions.refusal(%w[cn-north-1])
        assert_equal "Regions is required.", regions.refusal([])
        assert_equal %w[rollback_deployment restart_service scale_service], Aws.tool_definitions.reject(&:read_only).map(&:name)
        assert Aws.credential_fields.find { |field| field.key == Aws::SECRET_ACCESS_KEY }.secret
      end

      test "keys, regions and AWS's refusal are said on the form before anything is saved, asking AWS in the first region chosen" do
        regions = { Aws::REGIONS => %w[eu-west-1 us-east-1] }
        assert_equal "Paste an access key id.", Aws.credential_refusal({ Aws::SECRET_ACCESS_KEY => "x" }, fields: regions)
        assert_equal "Choose at least one region.", Aws.credential_refusal({ Aws::ACCESS_KEY_ID => "a", Aws::SECRET_ACCESS_KEY => "x" }, fields: {})

        AwsApi.any_instance.stubs(:identity).raises(AwsApi::Denied, "AWS answered InvalidClientTokenId: The security token included in the request is invalid.")
        assert_equal "AWS refused these keys: AWS answered InvalidClientTokenId: The security token included in the request is invalid.",
                     Aws.credential_refusal({ Aws::ACCESS_KEY_ID => "a", Aws::SECRET_ACCESS_KEY => "x" }, fields: regions)
        AwsApi.any_instance.expects(:identity).with("eu-west-1").returns(account: ACCOUNT)
        assert_nil Aws.credential_refusal({ Aws::ACCESS_KEY_ID => "a", Aws::SECRET_ACCESS_KEY => "x" }, fields: regions)
      end

      test "the health check asks AWS who the keys belong to" do
        assert_nothing_raised { @pack.check_health!(@row) }

        AwsApi.any_instance.stubs(:identity).raises(AwsApi::Denied, "AWS answered ExpiredToken: expired")
        assert_raises(NativePack::Error) { Aws.new(@integration).check_health!(@row) }
      end

      test "what the connection reaches is listed per kind with its region, state and ARN, and a list AWS refuses is said" do
        inventory!

        text = call(:list_resources)

        assert_match "ECS services:\nweb (#{SERVICE_ARN}), eu-west-1, degraded", text
        assert_match "Lambda functions:\ncheckout (#{FUNCTION_ARN}), eu-west-1, active", text
        assert_match "EC2 instances:\nbastion (#{INSTANCE_ARN}), eu-west-1, running", text
        assert_match "RDS databases:\norders (#{DATABASE_ARN}), eu-west-1, available", text
        assert_match "Lambda functions in us-east-1 could not be read: AWS answered AccessDeniedException", text
        assert_match "give the person this link with what you found: https://eu-west-1.console.aws.amazon.com/console/home?region=eu-west-1", text
        assert_match "kind must be one of", assert_raises(NativePack::Error) { call(:list_resources, "kind" => "bucket") }.message
        assert_match "does not read ap-south-1", assert_raises(NativePack::Error) { call(:list_resources, "region" => "ap-south-1") }.message
      end

      test "an ECS service is described with its rollout, containers, health checks and events, and its environment is only named" do
        answer(:describe_services, services: [ service(rollout: "IN_PROGRESS") ])

        text = call(:describe_resource, "resource" => SERVICE_ARN)

        assert_match "web, ECS service in cluster prod, eu-west-1, FARGATE, status ACTIVE", text
        assert_match "Tasks: 1 running, 1 pending, 2 wanted", text
        assert_match "primary, task definition web:42, rollout in_progress: ECS deployment ecs-svc/1 in progress., 1 of 2 running, 3 tasks failed to start", text
        assert_match "Deployment circuit breaker: on, rolls back", text
        assert_match "app: 123.dkr.ecr.eu-west-1.amazonaws.com/web:9f1c, essential, ports 8080/tcp, health check CMD-SHELL curl -f http://localhost:8080/up", text
        assert_match "environment variables DATABASE_URL, secrets STRIPE_KEY", text
        assert_no_match "hunter2", text
        assert_no_match "arn:aws:secretsmanager", text
        assert_match "2026-10-01T12:00:00Z (service web) is unable to consistently start tasks successfully.", text
        assert text.end_with?("https://eu-west-1.console.aws.amazon.com/ecs/v2?region=eu-west-1")
      end

      test "a Lambda function is described with its state and aliases, and its environment variables are only named" do
        answer(:get_function_configuration, function_name: "checkout", runtime: "nodejs22.x", handler: "index.handler", state: "Active",
                                            last_update_status: "Successful", last_modified: "2026-10-01T11:00:00.000+0000", memory_size: 512, timeout: 30,
                                            architectures: [ "arm64" ], version: "$LATEST", code_sha_256: "abc", environment: { variables: { "API_TOKEN" => "sk_live_123" } })
        answer(:list_aliases, aliases: [ { name: "live", function_version: "12", routing_config: { additional_version_weights: { "13" => 0.1 } } } ])

        text = call(:describe_resource, "resource" => FUNCTION_ARN)

        assert_match "checkout, Lambda function in eu-west-1, nodejs22.x, handler index.handler", text
        assert_match "Memory 512 MB, timeout 30s, arm64", text
        assert_match "Environment variables: API_TOKEN", text
        assert_no_match "sk_live_123", text
        assert_match "Aliases:\n  live points at version 12 with 10% to 13", text
        assert text.end_with?("https://eu-west-1.console.aws.amazon.com/lambda/home?region=eu-west-1#/functions")
      end

      test "an EC2 instance is described with its status checks and an RDS database with its storage, pending changes and events" do
        answer(:describe_instances, reservations: [ { owner_id: ACCOUNT, instances: [ instance ] } ])
        answer(:describe_instance_status, instance_statuses: [ { instance_id: "i-0abc", system_status: { status: "ok" }, instance_status: { status: "impaired" },
                                                                events: [ { code: "system-reboot", description: "Scheduled reboot", not_before: Time.utc(2026, 10, 3) } ] } ])
        answer(:describe_db_instances, db_instances: [ database(pending_modified_values: { db_instance_class: "db.r6g.large" }) ])
        answer(:describe_events, events: [ { date: Time.utc(2026, 10, 1, 9), message: "Backing up DB instance" },
                                           { date: Time.utc(2026, 10, 1, 10), message: "Multi-AZ instance failover started." } ])

        instance_text = call(:describe_resource, "resource" => INSTANCE_ARN)
        assert_match "Status checks: system ok, instance impaired", instance_text
        assert_match "Scheduled events: system-reboot Scheduled reboot from 2026-10-03T00:00:00Z", instance_text

        database_text = call(:describe_resource, "resource" => DATABASE_ARN)
        assert_match "orders, RDS database in eu-west-1, postgres 16.4, db.r6g.medium", database_text
        assert_match "Pending changes: db_instance_class db.r6g.large", database_text
        assert_match "Logs exported to CloudWatch: postgresql", database_text
        assert_match "Events in the last day, newest first:\n2026-10-01T10:00:00Z Multi-AZ instance failover started.\n2026-10-01T09:00:00Z Backing up", database_text
      end

      test "an ECS service's logs are read from its awslogs group and stream prefix, newest first, with the filters asked" do
        AwsApi.any_instance.expects(:call).with do |service, region, operation, params|
          service == :logs && region == "eu-west-1" && operation == :start_query && params[:log_group_names] == [ "/ecs/web" ] &&
            params[:query_string] == 'fields @timestamp, @logStream, @message | filter @logStream like "web/app/" | filter @message like "timeout" | ' \
                                     'filter @message not like "health" | filter @message like /5\d\d/ | sort @timestamp desc | limit 50'
        end.returns(query_id: "q-1")
        answer(:get_query_results, status: "Complete", results: [
          [ { field: "@timestamp", value: "2026-10-01 12:00:02.000" }, { field: "@logStream", value: "web/app/abc" }, { field: "@message", value: "upstream timeout 504" } ],
          [ { field: "@timestamp", value: "2026-10-01 12:00:01.000" }, { field: "@logStream", value: "web/app/abc" }, { field: "@message", value: "timeout 502" } ]
        ])

        text = call(:search_logs, "resource" => SERVICE_ARN, "text" => "timeout", "exclude" => "health", "regex" => "5\\d\\d", "limit" => 50)

        assert_match "2 log lines for web in /ecs/web", text
        assert_match "2026-10-01T12:00:02Z web/app/abc upstream timeout 504\n2026-10-01T12:00:01Z web/app/abc timeout 502", text
        assert text.end_with?("https://eu-west-1.console.aws.amazon.com/cloudwatch/home?region=eu-west-1#logs:")
      end

      test "a log search Logs Insights cannot write, or a resource with no logs in CloudWatch, says what to do instead" do
        AwsApi.any_instance.expects(:call).with { |_service, _region, operation, *| operation == :start_query }.never

        assert_match "double quote or a backslash", refusal(:search_logs, "resource" => SERVICE_ARN, "text" => "say \"hi\"")
        assert_match "forward slash", refusal(:search_logs, "resource" => SERVICE_ARN, "regex" => "GET /health")
        assert_match "sends no logs to CloudWatch Logs by itself", refusal(:search_logs, "resource" => INSTANCE_ARN)
        answer(:describe_db_instances, db_instances: [ database(enabled_cloudwatch_logs_exports: []) ])
        assert_match "exports no logs to CloudWatch Logs", refusal(:search_logs, "resource" => DATABASE_ARN)
        answer(:describe_task_definition, task_definition: task_definition(log_driver: "awsfirelens"))
        assert_match "does not send its logs to CloudWatch Logs (it uses awsfirelens)", refusal(:search_logs, "resource" => SERVICE_ARN)
      end

      test "a Lambda function's logs are read from its own log group" do
        answer(:get_function_configuration, function_name: "checkout", logging_config: { log_group: "/custom/checkout" })
        AwsApi.any_instance.expects(:call).with { |_service, _region, operation, params| operation == :start_query && params[:log_group_names] == [ "/custom/checkout" ] }
                    .returns(query_id: "q-2")
        answer(:get_query_results, status: "Complete", results: [])

        assert_match "No log lines matched checkout in /custom/checkout", call(:search_logs, "resource" => FUNCTION_ARN)
      end

      test "a Logs Insights query runs as written, and one still running after the wait is stopped and said" do
        AwsApi.any_instance.expects(:call).with { |_service, region, operation, params| region == "us-east-1" && operation == :start_query && params[:query_string] == "stats count(*) by bin(5m)" }
                    .returns(query_id: "q-3")
        answer(:get_query_results, status: "Complete", results: [ [ { field: "bin(5m)", value: "2026-10-01 12:00:00.000" }, { field: "count(*)", value: "42" } ] ])

        text = call(:logs_insights_query, "log_groups" => [ "/aws/lambda/checkout" ], "query" => "stats count(*) by bin(5m)", "region" => "us-east-1")
        assert_match "1 rows from /aws/lambda/checkout", text
        assert_match "bin(5m)=2026-10-01 12:00:00.000 count(*)=42", text

        answer(:start_query, query_id: "q-4")
        answer(:get_query_results, status: "Running", results: [])
        AwsApi.any_instance.expects(:call).with { |_service, _region, operation, params| operation == :stop_query && params[:query_id] == "q-4" }.returns(success: true)
        Aws.any_instance.stubs(:sleep).with { travel(Aws::QUERY_WAIT + 1); true }
        assert_match "did not finish within 25 seconds", refusal(:logs_insights_query, "log_groups" => [ "/ecs/web" ], "query" => "fields @message")
        answer(:get_query_results, status: "Failed")
        assert_match "ended the query as Failed", refusal(:logs_insights_query, "log_groups" => [ "/ecs/web" ], "query" => "fields @message")
      end

      test "metrics come from CloudWatch with the namespace, dimensions and statistic AWS documents, counts per minute, as charts" do
        AwsApi.any_instance.expects(:call).with do |service, region, operation, params|
          queries = params[:metric_data_queries]
          service == :cloudwatch && region == "eu-west-1" && operation == :get_metric_data &&
            queries.map { |query| [ query.dig(:metric_stat, :metric, :metric_name), query.dig(:metric_stat, :stat), query.dig(:metric_stat, :period) ] } ==
              [ [ "Invocations", "Sum", 60 ], [ "Duration", "Average", 60 ] ] &&
            queries.first.dig(:metric_stat, :metric) == { namespace: "AWS/Lambda", metric_name: "Invocations", dimensions: [ { name: "FunctionName", value: "checkout" } ] }
        end.returns(metric_data_results: [
          { id: "m0", timestamps: [ Time.utc(2026, 10, 1, 12, 1), Time.utc(2026, 10, 1, 12, 0) ], values: [ 120.0, 60.0 ] },
          { id: "m1", timestamps: [ Time.utc(2026, 10, 1, 12, 0) ], values: [ 250.0 ] }
        ])

        result = @pack.call("cloudwatch_metrics", environment_row: @row, arguments: { "resource" => FUNCTION_ARN, "metrics" => %w[Invocations Duration], "minutes" => 60 })

        text = result["content"].sole["text"]
        assert_match "Invocations of checkout (per minute)", text
        assert_match "min 60.0, avg 90.0, max 120.0", text
        assert_match "Duration, average of checkout (ms)", text
        charts = result.dig("structuredContent", "charts")
        assert_equal [ "Invocations of checkout", "Duration, average of checkout" ], charts.map { |chart| chart["title"] }
        assert_equal "https://eu-west-1.console.aws.amazon.com/cloudwatch/home?region=eu-west-1#metricsV2:graph=~();namespace=~'AWS*2fLambda", charts.first["link"]
        assert_match "has no MemoryUtilization in CloudWatch", refusal(:cloudwatch_metrics, "resource" => FUNCTION_ARN, "metrics" => [ "MemoryUtilization" ])
      end

      test "an ECS service's deployments say when, how each ended and what it rolled out, with the revisions to roll back to" do
        answer(:list_service_deployments, service_deployments: [
          { service_deployment_arn: "dep-old", created_at: Time.utc(2026, 9, 30), started_at: Time.utc(2026, 9, 30), status: "SUCCESSFUL", target_service_revision_arn: "rev-41" },
          { service_deployment_arn: "dep-new", created_at: Time.utc(2026, 10, 1), started_at: Time.utc(2026, 10, 1), status: "ROLLBACK_SUCCESSFUL",
            status_reason: "Service deployment rolled back because the circuit breaker threshold was exceeded.", target_service_revision_arn: "rev-42" }
        ])
        answer(:describe_service_deployments, service_deployments: [ { service_deployment_arn: "dep-new", rollback: { reason: "circuit breaker", started_at: Time.utc(2026, 10, 1, 0, 5) } } ])
        answer(:describe_service_revisions, service_revisions: [
          { service_revision_arn: "rev-42", task_definition: TASK_DEFINITION, container_images: [ { container_name: "app", image: "web:9f1c" } ] },
          { service_revision_arn: "rev-41", task_definition: TASK_DEFINITION.sub(":42", ":41") }
        ])
        answer(:list_task_definitions, task_definition_arns: [ TASK_DEFINITION, TASK_DEFINITION.sub(":42", ":41") ])

        text = call(:list_deployments, "resource" => SERVICE_ARN)

        assert_match "Latest 2 deployments of web, newest first.\n2026-10-01T00:00:00Z, rollback_successful, task definition web:42, images app web:9f1c", text
        assert_match "rolled back at 2026-10-01T00:05:00Z: circuit breaker", text
        assert_match "2026-09-30T00:00:00Z, successful, task definition web:41", text
        assert_match "It runs web:42. A rollback takes a revision of web: web:42 (running), web:41.", text
      end

      test "an ECS service's deployments carry their start, finish and status as run history" do
        answer(:list_service_deployments, service_deployments: [
          { service_deployment_arn: "arn:aws:ecs:eu-west-1:1:service-deployment/prod/web/dep-old", started_at: Time.utc(2026, 9, 30, 10), finished_at: Time.utc(2026, 9, 30, 10, 6),
            status: "SUCCESSFUL", target_service_revision_arn: "rev-41" },
          { service_deployment_arn: "arn:aws:ecs:eu-west-1:1:service-deployment/prod/web/dep-new", started_at: Time.utc(2026, 10, 1), status: "IN_PROGRESS",
            target_service_revision_arn: "rev-42" }
        ])
        answer(:describe_service_deployments, service_deployments: [])
        answer(:describe_service_revisions, service_revisions: [ { service_revision_arn: "rev-42", task_definition: TASK_DEFINITION } ])
        answer(:list_task_definitions, task_definition_arns: [ TASK_DEFINITION ])

        result = @pack.call("list_deployments", environment_row: @row, arguments: { "resource" => SERVICE_ARN })
        runs = Capabilities::History.runs_of(result)

        assert_equal [ [ "dep-new", "running", nil, "task definition web:42" ], [ "dep-old", "succeeded", 360, nil ] ],
                     runs.map { |run| [ run.id, run.status, run.seconds, run.detail ] }
        assert_match "https://eu-west-1.console.aws.amazon.com/ecs/v2", Capabilities::RunHistory.link_of(result).url
      end

      test "a service ECS has no deployment history for shows its current deployments instead" do
        answer(:list_service_deployments, raises: [ AwsApi::Error, "AWS answered InvalidParameterException: not supported" ])
        answer(:list_task_definitions, task_definition_arns: [ TASK_DEFINITION ])

        text = call(:list_deployments, "resource" => SERVICE_ARN)

        assert_match "ECS has no deployment history for web. It keeps the last 90 days", text
        assert_match "Deployments:\nprimary, task definition web:42", text
      end

      test "a Lambda function's versions are listed newest first with the alias on each" do
        AwsApi.any_instance.stubs(:all).with { |_service, _region, operation, *| operation == :list_versions_by_function }
                    .returns([ [ { version: "$LATEST" }, { version: "11", last_modified: "2026-09-30" }, { version: "12", last_modified: "2026-10-01", description: "Retry payments" } ], false ])
        answer(:list_aliases, aliases: [ { name: "live", function_version: "12" } ])

        text = call(:list_deployments, "resource" => FUNCTION_ARN)

        assert_match "Latest 2 versions of checkout, newest first. A rollback takes a version.\nversion 12, last modified 2026-10-01, \"Retry payments\"", text
        assert_match "alias live\nversion 11", text
        assert_match "only ECS services and Lambda functions have deployments", refusal(:list_deployments, "resource" => DATABASE_ARN)
      end

      test "an ECS service rolls back only to a revision of its own family, and says how to undo it" do
        AwsApi.any_instance.expects(:call).with { |_service, _region, operation, params| operation == :update_service && params == { cluster: "prod", service: SERVICE_ARN, task_definition: "web:41" } }
                    .returns(service: {})

        assert_match "web is rolling out web:41 in place of web:42. Undo by rolling back to web:42.", call(:rollback_deployment, "resource" => SERVICE_ARN, "to" => "web:41")
        assert_match "roll it back to a revision of web", refusal(:rollback_deployment, "resource" => SERVICE_ARN, "to" => "worker:3")
        assert_match "already runs web:42", refusal(:rollback_deployment, "resource" => SERVICE_ARN, "to" => "web:42")
        assert_match "task definition revision, such as web:41", refusal(:rollback_deployment, "resource" => SERVICE_ARN, "to" => "latest")
      end

      test "a Lambda function rolls back by moving its alias, and one with several aliases is told to name it" do
        answer(:list_aliases, aliases: [ { name: "live", function_version: "12" } ])
        AwsApi.any_instance.expects(:call).with { |_service, _region, operation, params| operation == :update_alias && params == { function_name: "checkout", name: "live", function_version: "11" } }
                    .returns({})

        assert_match "checkout's alias live now points at version 11 in place of 12. Undo by pointing it back at 12.", call(:rollback_deployment, "resource" => FUNCTION_ARN, "to" => "11")

        answer(:list_aliases, aliases: [ { name: "live", function_version: "12" }, { name: "canary", function_version: "13" } ])
        assert_match "more than one alias (live, canary), so say which, as alias:version", refusal(:rollback_deployment, "resource" => FUNCTION_ARN, "to" => "11")
        assert_match "has no alias beta", refusal(:rollback_deployment, "resource" => FUNCTION_ARN, "to" => "beta:11")
        answer(:list_aliases, aliases: [])
        assert_match "has no alias, so there is no traffic to move back", refusal(:rollback_deployment, "resource" => FUNCTION_ARN, "to" => "11")
      end

      test "a restart forces a new deployment and a scale sets the count, each saying how to undo it" do
        AwsApi.any_instance.expects(:call).with { |_service, _region, operation, params| operation == :update_service && params[:force_new_deployment] == true }.returns(service: {})
        assert_match "starting a new deployment on the task definition it runs", call(:restart_service, "resource" => SERVICE_ARN)

        AwsApi.any_instance.expects(:call).with { |_service, _region, operation, params| operation == :update_service && params[:desired_count] == 5 }.returns(service: {})
        assert_match "web now wants 5 tasks, up from 2. Undo by scaling it back to 2.", call(:scale_service, "resource" => SERVICE_ARN, "desired_count" => 5)
        assert_match "desired_count must be a whole number", refusal(:scale_service, "resource" => SERVICE_ARN, "desired_count" => -1)
        assert_match "only ECS services can be restarted here", refusal(:restart_service, "resource" => FUNCTION_ARN)
      end

      test "a change the access key's policy refuses says to allow the action AWS named" do
        answer(:update_service, raises: [ AwsApi::Denied, "AWS answered AccessDeniedException: User: arn:aws:iam::#{ACCOUNT}:user/firefight is not authorized to perform: ecs:UpdateService" ])

        message = refusal(:restart_service, "resource" => SERVICE_ARN)

        assert_match "not authorized to perform: ecs:UpdateService. The access key's policy does not allow this change to web", message
        assert_match "Allow the action AWS names in the policy of the access key's IAM user", message
      end

      test "an ECS service's tasks say why each stopped" do
        answer(:list_tasks, task_arns: [ "arn:aws:ecs:eu-west-1:#{ACCOUNT}:task/prod/abc" ])
        answer(:describe_tasks, tasks: [
          { task_arn: "arn:aws:ecs:eu-west-1:#{ACCOUNT}:task/prod/abc", last_status: "STOPPED", task_definition_arn: TASK_DEFINITION, created_at: Time.utc(2026, 10, 1, 12),
            started_at: Time.utc(2026, 10, 1, 12), stopped_at: Time.utc(2026, 10, 1, 12, 3), stop_code: "EssentialContainerExited",
            stopped_reason: "Essential container in task exited", containers: [ { name: "app", last_status: "STOPPED", exit_code: 137, reason: "OutOfMemoryError: Container killed due to memory usage" } ] }
        ])

        text = call(:list_tasks, "resource" => SERVICE_ARN)

        assert_match "web: 0 running, 1 stopped recently", text
        assert_match "abc, stopped, task definition web:42, started 2026-10-01T12:00:00Z, stopped 2026-10-01T12:03:00Z, EssentialContainerExited: Essential container in task exited, " \
                     "containers app stopped exit code 137 OutOfMemoryError: Container killed due to memory usage", text
      end

      test "a resource is found by name, a name two resources share lists their ARNs, and one outside the connection's regions is refused" do
        inventory!
        answer(:list_tasks, task_arns: [])
        assert_match "web has no running tasks", call(:list_tasks, "resource" => "web")
        assert_equal SERVICE_ARN, @pack.send(:find_resource, @row, "WEB").arn
        assert_equal INSTANCE_ARN, @pack.send(:find_resource, @row, "i-0abc").arn

        AwsApi.any_instance.stubs(:all).with { |_service, region, operation, *| operation == :list_functions && region == "eu-west-1" }
                    .returns([ [ function, function.merge(function_name: "web", function_arn: FUNCTION_ARN.sub("checkout", "web")) ], false ])
        assert_match "More than one AWS resource is called web: ECS service #{SERVICE_ARN}, Lambda function #{FUNCTION_ARN.sub("checkout", "web")}. Name it by its id.", refusal(:describe_resource, "resource" => "web")
        assert_match "Nothing called nope in eu-west-1, us-east-1", refusal(:describe_resource, "resource" => "nope")
        assert_match "is in ap-south-1, which this connection does not read", refusal(:describe_resource, "resource" => FUNCTION_ARN.sub("eu-west-1", "ap-south-1"))
      end

      test "an ECS service whose rollout completed reads degraded while it runs fewer tasks than it wants, and completed once it runs them all" do
        assert_equal "degraded", @pack.send(:service_entry, service, "eu-west-1").status
        assert_equal "completed", @pack.send(:service_entry, service.merge(running_count: 2), "eu-west-1").status
        assert_equal "in_progress", @pack.send(:service_entry, service(rollout: "IN_PROGRESS"), "eu-west-1").status
      end

      test "the account goes on the map with each resource's kind, ARN, page and details, and a list AWS refused is not taken as gone" do
        inventory!

        snapshot = @pack.map_of(@row)

        found = snapshot.resources.index_by(&:external_id)
        assert_equal [ ResourceMap::KIND_SERVICE, ACCOUNT, "web", "degraded", "https://eu-west-1.console.aws.amazon.com/ecs/v2?region=eu-west-1" ],
                     found[SERVICE_ARN].then { |resource| [ resource.kind, resource.account, resource.name, resource.status, resource.url ] }
        assert_equal({ "region" => "eu-west-1", "type" => "FARGATE", "instances" => 2, "cluster" => "prod", "task_definition" => "web:42" }, found[SERVICE_ARN].details)
        assert_equal [ ResourceMap::KIND_FUNCTION, "active" ], found[FUNCTION_ARN].then { |resource| [ resource.kind, resource.status ] }
        assert_equal [ ResourceMap::KIND_VIRTUAL_MACHINE, "bastion", "t3.micro" ], found[INSTANCE_ARN].then { |resource| [ resource.kind, resource.name, resource.details["type"] ] }
        assert_equal [ ResourceMap::KIND_DATABASE, "postgres 16.4" ], found[DATABASE_ARN].then { |resource| [ resource.kind, resource.details["engine"] ] }
        assert_equal [ ResourceMap::KIND_FUNCTION ], snapshot.unread_kinds
        assert_match "Lambda functions in us-east-1 could not be read: AWS answered AccessDeniedException", snapshot.gaps.sole.text
        assert_equal [ ResourceMap::KIND_FUNCTION ], snapshot.gaps.sole.kinds
      end

      test "an instance's and a database's tags are kept in their details for finding them by, and none leaves the key out" do
        assert_equal({ "Name" => "bastion" }, @pack.send(:instance_entry, instance, ACCOUNT, "eu-west-1").details[ResourceMap::TAGS])
        tagged = database(tag_list: [ { key: "team", value: "payments" }, { key: "env", value: "prod" } ])
        assert_equal({ "team" => "payments", "env" => "prod" }, @pack.send(:database_entry, tagged, "eu-west-1").details[ResourceMap::TAGS])
        assert_not @pack.send(:database_entry, database, "eu-west-1").details.key?(ResourceMap::TAGS)
      end

      test "the map reads ECS services' tags with DescribeServices and Lambda functions' with ListTags, and only the map asks for them" do
        inventory!
        AwsApi.any_instance.expects(:call).with(:ecs, "eu-west-1", :describe_services, cluster: CLUSTER_ARN, services: [ SERVICE_ARN ], include: [ Aws::TAGS ])
              .returns(services: [ service.merge(tags: [ { key: "team", value: "payments" } ]) ])
        AwsApi.any_instance.expects(:call).with(:lambda, "eu-west-1", :list_tags, resource: FUNCTION_ARN).returns(tags: { "team" => "checkout" })

        found = @pack.map_of(@row).resources.index_by(&:external_id)

        assert_equal({ "team" => "payments" }, found[SERVICE_ARN].details[ResourceMap::TAGS])
        assert_equal({ "team" => "checkout" }, found[FUNCTION_ARN].details[ResourceMap::TAGS])
        assert_not @pack.send(:function_entry, function, "eu-west-1").details.key?(ResourceMap::TAGS)

        AwsApi.any_instance.expects(:call).with { |_service, _region, operation, *| operation == :list_tags }.never
        AwsApi.any_instance.expects(:call).with { |_service, _region, operation, params| operation == :describe_services && params.key?(:include) }.never
        call(:list_resources, {})
      end

      test "a change names one resource, read again as the sweep reads it with its tags and settings, and one AWS no longer has is gone" do
        AwsApi.any_instance.expects(:call).with(:ecs, "eu-west-1", :describe_services, cluster: "prod", services: [ SERVICE_ARN ], include: [ Aws::TAGS ])
              .returns(services: [ service.merge(tags: [ { key: "team", value: "payments" } ]) ])

        refreshed = @pack.map_refresh(@row, scope(ResourceMap::KIND_SERVICE, SERVICE_ARN))

        found = refreshed.resources.sole
        assert_equal [ service_key, "degraded", { "team" => "payments" } ], [ found.key, found.status, found.details[ResourceMap::TAGS] ]
        assert_equal [ "DATABASE_URL", "STRIPE_KEY" ], refreshed.uses.map(&:variable).sort, "a re-read refreshes where its settings point"
        assert_empty refreshed.gone

        AwsApi.any_instance.unstub(:call)
        answer(:describe_services, services: [ service.merge(status: "INACTIVE") ])
        assert_equal [ service_key ], @pack.map_refresh(@row, scope(ResourceMap::KIND_SERVICE, SERVICE_ARN)).gone, "an inactive service is one the sweep no longer lists"

        answer(:get_function_configuration, raises: [ AwsApi::NotFound, "AWS answered ResourceNotFoundException: Function not found" ])
        assert_equal [ function_key ], @pack.map_refresh(@row, scope(ResourceMap::KIND_FUNCTION, FUNCTION_ARN)).gone
      end

      test "a function, an instance and a database are each read again on their own" do
        settings = { variables: { "DATABASE_URL" => "postgres://app:hunter2@orders.abc.eu-west-1.rds.amazonaws.com/orders" } }
        answer(:get_function_configuration, **function.merge(function_arn: "#{FUNCTION_ARN}:$LATEST", environment: settings))
        answer(:list_tags, tags: { "team" => "checkout" })
        function_read = @pack.map_refresh(@row, scope(ResourceMap::KIND_FUNCTION, FUNCTION_ARN))
        assert_equal [ function_key, { "team" => "checkout" } ], [ function_read.resources.sole.key, function_read.resources.sole.details[ResourceMap::TAGS] ]
        assert_equal [ "DATABASE_URL" ], function_read.uses.map(&:variable)

        answer(:describe_instances, reservations: [ { owner_id: ACCOUNT, instances: [ instance ] } ])
        assert_equal "running", @pack.map_refresh(@row, scope(ResourceMap::KIND_VIRTUAL_MACHINE, INSTANCE_ARN)).resources.sole.status
        answer(:describe_instances, reservations: [ { owner_id: ACCOUNT, instances: [ instance.merge(state: { name: "terminated" }) ] } ])
        assert_equal [ [ "aws", ACCOUNT, ResourceMap::KIND_VIRTUAL_MACHINE, INSTANCE_ARN ] ], @pack.map_refresh(@row, scope(ResourceMap::KIND_VIRTUAL_MACHINE, INSTANCE_ARN)).gone

        AwsApi.any_instance.expects(:call).with(:rds, "eu-west-1", :describe_db_instances, db_instance_identifier: DATABASE_ARN)
              .returns(db_instances: [ database(endpoint: { address: "orders.abc.eu-west-1.rds.amazonaws.com", port: 5432 }) ])
        database_read = @pack.map_refresh(@row, scope(ResourceMap::KIND_DATABASE, DATABASE_ARN))
        assert_equal "available", database_read.resources.sole.status
        assert_equal 1, database_read.endpoints.size
      end

      test "a change the connection cannot narrow is swept, and one outside its regions or account changes nothing" do
        AwsApi.any_instance.expects(:call).never

        assert_nil @pack.map_refresh(@row, ResourceMap::Scope.everything)
        assert_nil @pack.map_refresh(@row, ResourceMap::Scope.new(account: ACCOUNT, kind: ResourceMap::KIND_SERVICE))
        assert_nil @pack.map_refresh(@row, scope(ResourceMap::KIND_SERVICE, "arn:aws:ecs:eu-west-1:#{ACCOUNT}:service/web")), "an older service ARN does not name its cluster"
        elsewhere = @pack.map_refresh(@row, scope(ResourceMap::KIND_SERVICE, SERVICE_ARN.sub("eu-west-1", "ap-south-1")))
        assert_equal [ [], [] ], [ elsewhere.resources, elsewhere.gone ]
        other = @pack.map_refresh(@row, ResourceMap::Scope.new(account: "999999999999", kind: ResourceMap::KIND_SERVICE, external_id: SERVICE_ARN))
        assert_equal [ [], [] ], [ other.resources, other.gone ]
      end

      test "a key that may not read tags still puts every service and function on the map, without tags, with a gap that holds nothing back" do
        inventory!
        denied = "AWS answered AccessDeniedException: not authorized to perform: ecs:ListTagsForResource"
        AwsApi.any_instance.stubs(:call).with { |_service, _region, operation, params| operation == :describe_services && params.key?(:include) }.raises(AwsApi::Denied, denied)
        AwsApi.any_instance.stubs(:call).with { |_service, _region, operation, params| operation == :describe_services && !params.key?(:include) }.returns(services: [ service ])
        answer(:list_tags, raises: [ AwsApi::Denied, "AWS answered AccessDeniedException: not authorized to perform: lambda:ListTags" ])

        snapshot = @pack.map_of(@row)

        found = snapshot.resources.index_by(&:external_id)
        assert_equal "web", found[SERVICE_ARN].name
        assert_equal "checkout", found[FUNCTION_ARN].name
        assert_not found[SERVICE_ARN].details.key?(ResourceMap::TAGS)
        tag_gaps = snapshot.gaps.select { |gap| gap.text.start_with?("Tags of") }
        assert_equal [ "Tags of ECS services in eu-west-1 could not be read, so they are on the map without them: #{denied}.",
                       "Tags of Lambda functions in eu-west-1 could not be read, so they are on the map without them: AWS answered AccessDeniedException: not authorized to perform: lambda:ListTags." ],
                     tag_gaps.map(&:text)
        assert tag_gaps.all? { |gap| gap.kinds.empty? }
        assert_equal [ ResourceMap::KIND_FUNCTION ], snapshot.unread_kinds, "only the Lambda list refused in us-east-1 holds anything back"
      end

      test "being asked to slow down while reading a function's tags stops the map's read like any list" do
        inventory!
        answer(:list_tags, raises: [ AwsApi::RateLimited, "AWS answered TooManyRequestsException: Rate exceeded" ])

        snapshot = @pack.map_of(@row)

        assert_equal Aws::KIND_NAMES.keys, snapshot.unread_kinds
        assert_match "AWS asked to slow down while listing Lambda functions in eu-west-1", snapshot.gaps.last.text
      end

      test "being asked to slow down stops the map's read, with every kind left unread" do
        AwsApi.any_instance.stubs(:all).raises(AwsApi::RateLimited, "AWS answered ThrottlingException: Rate exceeded")

        snapshot = @pack.map_of(@row)

        assert_empty snapshot.resources
        assert_equal Aws::KIND_NAMES.keys, snapshot.unread_kinds
        assert_match "AWS asked to slow down while listing ECS services in eu-west-1", snapshot.gaps.sole.text
      end

      test "the map reads each service's and function's settings in memory and each database's address and password secret, keeping no value" do
        inventory!
        secret = "arn:aws:secretsmanager:eu-west-1:#{ACCOUNT}:secret:rds!db-1-AbCdEf"
        AwsApi.any_instance.stubs(:all).with { |_service, at, called, *| called == :list_functions && at == "eu-west-1" }
              .returns([ [ function.merge(environment: { variables: { "API_TOKEN" => "sk_live_123", "REDIS_URL" => "rediss://default:redispw@cache.example.com:6380" } }) ], false ])
        AwsApi.any_instance.stubs(:all).with { |_service, at, called, *| called == :describe_db_instances && at == "eu-west-1" }
              .returns([ [ database(endpoint: { address: "orders.abc.eu-west-1.rds.amazonaws.com", port: 5432 }, master_user_secret: { secret_arn: secret }) ], false ])
        AwsApi.any_instance.expects(:call).with(:ecs, "eu-west-1", :describe_task_definition, task_definition: TASK_DEFINITION).once
              .returns(task_definition: task_definition(secrets: [ { name: "DATABASE_PASSWORD", value_from: "#{secret}:password::" } ]))

        snapshot = @pack.map_of(@row)

        uses = snapshot.uses.group_by(&:from).transform_values { |found| found.map(&:variable).sort }
        assert_equal({ service_key => %w[DATABASE_PASSWORD DATABASE_URL], function_key => %w[REDIS_URL] }, uses)
        assert_equal [ 5432, 0 ], snapshot.endpoints.map(&:port)
        assert snapshot.endpoints.all? { |found| found.resource == [ "aws", ACCOUNT, ResourceMap::KIND_DATABASE, DATABASE_ARN ] }
        assert_no_setting_values(snapshot, "hunter2", "postgres://app:hunter2@db/prod", "sk_live_123", "redispw", "cache.example.com",
                                 "orders.abc.eu-west-1.rds.amazonaws.com")

        ResourceMap.record!(@row, snapshot)
        ResourceMap::Matcher.new(@workspace).run!
        link = ResourceMap::Link.find_by!(workspace: @workspace, origin: ResourceMap::ORIGIN_MATCHED)
        assert_equal [ "web", "orders", [ "DATABASE_PASSWORD" ] ], [ link.from_resource.name, link.to_resource.name, link.variables ]
        assert_no_setting_values(snapshot, "hunter2", "sk_live_123", "redispw", "orders.abc.eu-west-1.rds.amazonaws.com")
      end

      test "a function whose variables Lambda could not decrypt, and task definitions the key may not read, are gaps that hold no resource back" do
        inventory!
        AwsApi.any_instance.stubs(:all).with { |_service, at, called, *| called == :list_functions && at == "eu-west-1" }
              .returns([ [ function.merge(environment: { error: { error_code: "KMSAccessDeniedException", message: "Lambda was unable to decrypt the environment variables." } }) ], false ])
        answer(:describe_task_definition, raises: [ AwsApi::Denied, "AWS answered AccessDeniedException: not authorized to perform: ecs:DescribeTaskDefinition" ])

        snapshot = @pack.map_of(@row)

        assert_equal %w[checkout web], snapshot.resources.map(&:name).select { |name| %w[checkout web].include?(name) }.sort
        settings = snapshot.gaps.select(&:settings)
        assert_equal [ "The settings of ECS services in eu-west-1 could not be read. Allow ecs:DescribeTaskDefinition to read them: AWS answered AccessDeniedException: not authorized to perform: ecs:DescribeTaskDefinition.",
                       "The settings of Lambda function checkout could not be read: Lambda was unable to decrypt the environment variables." ],
                     settings.map(&:text).sort
        assert settings.all? { |gap| gap.kinds.empty? }
        assert_empty snapshot.uses
        assert_not snapshot.settings_complete?
      end

      test "a week of metrics per resource an hour a point, counts made per minute, and a slow down stops the read" do
        function_resource = ResourceMap::Resource.new(provider: "aws", account: ACCOUNT, kind: ResourceMap::KIND_FUNCTION, external_id: FUNCTION_ARN, name: "checkout")
        database_resource = ResourceMap::Resource.new(provider: "aws", account: ACCOUNT, kind: ResourceMap::KIND_DATABASE, external_id: DATABASE_ARN, name: "orders")
        repository = ResourceMap::Resource.new(provider: "github", account: "acme", kind: ResourceMap::KIND_REPOSITORY, external_id: "acme/app", name: "acme/app")
        hours = [ Time.utc(2026, 10, 1, 10), Time.utc(2026, 10, 1, 11) ]
        AwsApi.any_instance.stubs(:call).with { |_service, _region, operation, params| operation == :get_metric_data && params[:metric_data_queries].first.dig(:metric_stat, :metric, :namespace) == "AWS/Lambda" }
                    .returns(metric_data_results: [ { id: "m0", timestamps: hours, values: [ 600.0, 1200.0 ] } ])
        AwsApi.any_instance.stubs(:call).with { |_service, _region, operation, params| operation == :get_metric_data && params[:metric_data_queries].first.dig(:metric_stat, :metric, :namespace) == "AWS/RDS" }
                    .raises(AwsApi::NotFound, "AWS answered DBInstanceNotFound")

        found = @pack.baselines_of(@row, [ function_resource, database_resource, repository ], 7.days.ago..Time.current)

        assert_equal [ [ "Invocations", "per minute", [ 10.0, 20.0 ] ] ], found.map { |each| [ each.label, each.unit, each.points.map(&:last) ] }
        assert_equal function_resource.key, found.sole.key

        AwsApi.any_instance.stubs(:call).with { |_service, _region, operation, *| operation == :get_metric_data }.raises(AwsApi::RateLimited, "AWS answered Throttling")
        assert_raises(AwsApi::RateLimited) { @pack.baselines_of(@row, [ function_resource ], 7.days.ago..Time.current) }
      end

      test "AWS's skills cover triage and each kind, and the guides behind them carry AWS's license and notice" do
        skills = Chat::Skill.all.select { |skill| skill.source == Aws::PROVIDER_KEY }

        assert_equal %w[aws_ec2 aws_ecs aws_lambda aws_logs_insights aws_rds aws_triage], skills.map(&:name).sort
        skills.each { |skill| assert skill.references.any?, "#{skill.name} lists the guides behind it" }
        references = Chat::Skill::DIRECTORY.join(Aws::PROVIDER_KEY, Chat::Skill::REFERENCES)
        assert_match "Apache License", references.join("LICENSE").read
        assert_match "Amazon.com", references.join("NOTICE").read
        assert_match "Status check failed", Chat::Skill.reference(Aws::PROVIDER_KEY, "compute/troubleshooting.md")
      end

      test "every state AWS reports for a resource on the map reads a health Firefight knows" do
        provider = Integrations::Provider.for(Aws::PROVIDER_KEY)
        reported = {
          "ECS service" => %w[completed in_progress failed active draining inactive],
          "Lambda function" => %w[pending active inactive failed deactivating deactivated activenoninvocable deleting],
          "EC2 instance" => %w[pending running shutting-down terminated stopping stopped],
          "RDS database" => %w[
            available backing-up configuring-enhanced-monitoring configuring-iam-database-auth configuring-log-exports converting-to-vpc
            creating delete-precheck deleting failed inaccessible-encryption-credentials inaccessible-encryption-credentials-recoverable
            incompatible-create incompatible-network incompatible-option-group incompatible-parameters incompatible-restore
            insufficient-capacity maintenance modifying moving-to-vpc rebooting resetting-master-credentials renaming restore-error
            starting stopped stopping storage-config-upgrade storage-full storage-initialization storage-optimization upgrading upgrade-failed
          ]
        }
        reported.each do |kind, words|
          words.each do |word|
            health = ResourceMap::Resource.new(status: provider.status_of(word)).health
            assert_not_equal ResourceMap::Resource::HEALTH_UNKNOWN, health, "#{kind} #{word}"
          end
        end
        assert_equal "ok", ResourceMap::Resource.new(status: provider.status_of("available")).health
        assert_equal "failing", ResourceMap::Resource.new(status: provider.status_of("storage-full")).health
      end

      private

      def call(tool, arguments = {})
        @pack.call(tool.to_s, environment_row: @row, arguments: arguments)["content"].sole["text"]
      end

      def refusal(tool, arguments)
        assert_raises(NativePack::Error) { Aws.new(@integration).call(tool.to_s, environment_row: @row, arguments: arguments) }.message
      end

      def answer(operation, raises: nil, **returned)
        stub = AwsApi.any_instance.stubs(:call).with { |_service, _region, called, *| called == operation }
        raises ? stub.raises(*raises) : stub.returns(returned)
      end

      def inventory!
        listing = ->(operation, region, rows) { AwsApi.any_instance.stubs(:all).with { |_service, at, called, *| called == operation && at == region }.returns([ rows, false ]) }
        listing.call(:list_clusters, "eu-west-1", [ CLUSTER_ARN ])
        listing.call(:list_services, "eu-west-1", [ SERVICE_ARN ])
        listing.call(:list_functions, "eu-west-1", [ function ])
        listing.call(:describe_instances, "eu-west-1", [ { owner_id: ACCOUNT, instances: [ instance ] } ])
        listing.call(:describe_db_instances, "eu-west-1", [ database ])
        %i[list_clusters describe_instances describe_db_instances].each { |operation| listing.call(operation, "us-east-1", []) }
        AwsApi.any_instance.stubs(:all).with { |_service, region, called, *| called == :list_functions && region == "us-east-1" }
                    .raises(AwsApi::Denied, "AWS answered AccessDeniedException: not authorized to perform: lambda:ListFunctions")
        answer(:list_tags, tags: {})
      end

      def service(rollout: "COMPLETED")
        {
          service_arn: SERVICE_ARN, service_name: "web", cluster_arn: CLUSTER_ARN, status: "ACTIVE", desired_count: 2, running_count: 1, pending_count: 1,
          launch_type: "FARGATE", task_definition: TASK_DEFINITION,
          deployments: [ { status: "PRIMARY", task_definition: TASK_DEFINITION, desired_count: 2, running_count: 1, failed_tasks: 3, rollout_state: rollout,
                           rollout_state_reason: "ECS deployment ecs-svc/1 in progress.", created_at: Time.utc(2026, 10, 1, 11) } ],
          deployment_configuration: { deployment_circuit_breaker: { enable: true, rollback: true } },
          events: [ { created_at: Time.utc(2026, 10, 1, 12), message: "(service web) is unable to consistently start tasks successfully." } ]
        }
      end

      def service_key = [ "aws", ACCOUNT, ResourceMap::KIND_SERVICE, SERVICE_ARN ]

      def scope(kind, arn) = ResourceMap::Scope.new(account: ACCOUNT, kind: kind, external_id: arn)

      def function_key = [ "aws", ACCOUNT, ResourceMap::KIND_FUNCTION, FUNCTION_ARN ]

      def task_definition(log_driver: "awslogs", secrets: nil)
        {
          family: "web", revision: 42, cpu: "512", memory: "1024",
          container_definitions: [ {
            name: "app", image: "123.dkr.ecr.eu-west-1.amazonaws.com/web:9f1c", essential: true, port_mappings: [ { container_port: 8080, protocol: "tcp" } ],
            health_check: { command: [ "CMD-SHELL", "curl -f http://localhost:8080/up" ], interval: 30, retries: 3 },
            environment: [ { name: "DATABASE_URL", value: "postgres://app:hunter2@db/prod" } ],
            secrets: secrets || [ { name: "STRIPE_KEY", value_from: "arn:aws:secretsmanager:eu-west-1:#{ACCOUNT}:secret:stripe" } ],
            log_configuration: { log_driver: log_driver, options: { "awslogs-group" => "/ecs/web", "awslogs-stream-prefix" => "web", "awslogs-region" => "eu-west-1" } }
          } ]
        }
      end

      def function
        { function_name: "checkout", function_arn: FUNCTION_ARN, runtime: "nodejs22.x", state: "Active", last_update_status: "Successful",
          environment: { variables: { "API_TOKEN" => "sk_live_123" } } }
      end

      def instance
        { instance_id: "i-0abc", instance_type: "t3.micro", state: { name: "running" }, tags: [ { key: "Name", value: "bastion" } ],
          placement: { availability_zone: "eu-west-1a" }, launch_time: Time.utc(2026, 9, 1), image_id: "ami-123" }
      end

      def database(**overrides)
        { db_instance_identifier: "orders", db_instance_arn: DATABASE_ARN, db_instance_status: "available", engine: "postgres", engine_version: "16.4",
          db_instance_class: "db.r6g.medium", allocated_storage: 100, storage_type: "gp3", multi_az: true, availability_zone: "eu-west-1b",
          backup_retention_period: 7, latest_restorable_time: Time.utc(2026, 10, 1, 11, 55), enabled_cloudwatch_logs_exports: [ "postgresql" ] }.merge(overrides)
      end
    end
  end
end
