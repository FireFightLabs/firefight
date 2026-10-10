require "test_helper"

module Integrations
  module ReadGuards
    class AwsTest < ActiveSupport::TestCase
      test "a Describe, List, Get or BatchGet operation the service defines reads, by AWS's name or the SDK's, with its input in the SDK's shapes" do
        read = Aws.reading(ApiReads::TOOL, "service" => "ECS", "operation" => "DescribeServices",
                                           "params" => { "Cluster" => "prod", "services" => [ "web" ], "include" => [ "TAGS" ] })

        assert_equal({ "service" => "ecs", "operation" => "describe_services", "params" => { cluster: "prod", services: [ "web" ], include: [ "TAGS" ] } }, read)
        assert Aws.reads?(ApiReads::TOOL, "service" => "elbv2", "operation" => "describe_target_health", "params" => { "target_group_arn" => "arn:x" })
        assert Aws.reads?(ApiReads::TOOL, "service" => "sts", "operation" => "GetCallerIdentity")
        assert Aws.guards?(ApiReads::TOOL)
      end

      test "a map keeps its own keys and a time is read from ISO 8601" do
        read = Aws.reading(ApiReads::TOOL, "service" => "dynamodb", "operation" => "GetItem",
                                           "params" => { "TableName" => "orders", "Key" => { "OrderId" => { "S" => "o-1" } } })
        assert_equal({ "OrderId" => { s: "o-1" } }, read["params"][:key])

        events = Aws.reading(ApiReads::TOOL, "service" => "cloudformation", "operation" => "DescribeStackEvents", "params" => { "stack_name" => "app" })
        assert_equal "app", events["params"][:stack_name]
        logs = Aws.reading(ApiReads::TOOL, "service" => "logs", "operation" => "GetLogEvents",
                                           "params" => { "log_group_name" => "g", "log_stream_name" => "s", "start_time" => "1700000000000" })
        assert_equal 1_700_000_000_000, logs["params"][:start_time]
      end

      test "an operation that changes something, or one no client defines, is never called" do
        assert_raises(PolicyRefusal) { Aws.reading(ApiReads::TOOL, "service" => "ecs", "operation" => "UpdateService", "params" => {}) }
        assert_raises(Refused) { Aws.reading(ApiReads::TOOL, "service" => "ecs", "operation" => "get_waiter") }
        assert_raises(Refused) { Aws.reading(ApiReads::TOOL, "service" => "ecs", "operation" => "wait_until") }
        assert_raises(Refused) { Aws.reading(ApiReads::TOOL, "service" => "glacier", "operation" => "ListVaults") }
        error = assert_raises(Refused) { Aws.reading(ApiReads::TOOL, "service" => "ecs", "operation" => "DescribeServices", "params" => { "clusterName" => "x" }) }
        assert_match "It takes cluster, services, include", error.message
        assert_not Aws.reads?(ApiReads::TOOL, "service" => "ecs", "operation" => "DeleteService")
      end

      test "reads that answer a credential or a secret's value are refused by Firefight's rule" do
        [
          %w[secretsmanager GetSecretValue], %w[secretsmanager BatchGetSecretValue], %w[ssm GetParameter], %w[ssm GetParameters],
          %w[ssm GetParametersByPath], %w[ssm GetParameterHistory], %w[sts GetSessionToken], %w[sts GetFederationToken],
          %w[ecr GetAuthorizationToken], %w[ecr GetDownloadUrlForLayer], %w[ec2 GetPasswordData], %w[kms GetParametersForImport],
          %w[s3 GetObject], %w[apigateway GetUsagePlanKeys]
        ].each do |service, operation|
          assert_raises(PolicyRefusal, "#{service} #{operation}") { Aws.reading(ApiReads::TOOL, "service" => service, "operation" => operation) }
        end
        assert Aws.reads?(ApiReads::TOOL, "service" => "secretsmanager", "operation" => "ListSecrets")
        assert Aws.reads?(ApiReads::TOOL, "service" => "ssm", "operation" => "DescribeParameters")
        assert_raises(PolicyRefusal) { Aws.reading(ApiReads::TOOL, "service" => "apigateway", "operation" => "GetApiKeys", "params" => { "include_values" => true }) }
      end

      test "an environment, user data and a presigned link are hidden from what is answered" do
        shown = Aws.hidden(
          container_definitions: [ { name: "web", environment: [ { name: "DATABASE_URL", value: "postgres://u:pw@h/db" } ] } ],
          configuration: { environment: { variables: { "STRIPE_KEY" => "sk_live_1" } } }, user_data: "IyEvYmluL2Jhc2g=",
          code: { location: "https://awslambda.s3.amazonaws.com/x.zip?X-Amz-Signature=abc", repository_type: "S3" }
        )

        assert_equal "DATABASE_URL", shown[:container_definitions].first[:environment].first[:name]
        assert_equal ApiReads::HIDDEN, shown[:container_definitions].first[:environment].first[:value]
        assert_equal ApiReads::HIDDEN, shown.dig(:configuration, :environment, :variables, "STRIPE_KEY")
        assert_equal ApiReads::HIDDEN, shown[:user_data]
        assert_equal ApiReads::HIDDEN, shown.dig(:code, :location)
        assert_equal "S3", shown.dig(:code, :repository_type)
      end
    end
  end
end
