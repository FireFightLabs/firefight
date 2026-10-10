require "test_helper"

module Integrations
  module Packs
    # AWS's general read, api_read, one operation of one service in one of the connection's regions.
    class AwsReadsTest < ActiveSupport::TestCase
      setup do
        @integration = Integration.create!(workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_NATIVE, provider: "aws", name: "AWS")
        @row = @integration.integration_environments.create!
        Aws.store_credentials!(@row, Aws::ACCESS_KEY_ID => "AKIAEXAMPLE", Aws::SECRET_ACCESS_KEY => "secret")
        @row.store_fields!(Aws::REGIONS => %w[eu-west-1 us-east-1])
        @pack = Aws.new(@integration)
      end

      test "api_read only reads, so a member holds it without a grant and a chat never asks before it" do
        definition = Aws.tool_definitions.find { |each| each.name == ApiReads::TOOL }

        assert definition.read_only
        assert_equal %w[service operation], definition.params_schema["required"]
        assert_equal ReadGuards::Aws, Provider.for("aws").read_guard
      end

      test "an operation is called in the region asked with its input in the SDK's shapes, and links the service's console page" do
        AwsApi.any_instance.expects(:call).with(:elbv2, "eu-west-1", :describe_target_health, { target_group_arn: "arn:tg" })
              .returns(target_health_descriptions: [ { target: { id: "i-1", port: 80 }, target_health: { state: "unhealthy", reason: "Target.Timeout" } } ])

        result = call("service" => "elbv2", "operation" => "DescribeTargetHealth", "params" => { "TargetGroupArn" => "arn:tg" }, "region" => "eu-west-1")

        assert_match "AWS answered elbv2 DescribeTargetHealth in eu-west-1.", text(result)
        assert_match "Target.Timeout", text(result)
        assert_includes text(result), "https://eu-west-1.console.aws.amazon.com/ec2/home?region=eu-west-1"
      end

      test "a region the connection does not read is refused, and one must be named when it reads several" do
        AwsApi.any_instance.expects(:call).never

        assert_raises(PolicyRefusal) { call("service" => "ecs", "operation" => "ListClusters", "region" => "ap-south-1") }
        error = assert_raises(NativePack::Error) { call("service" => "ecs", "operation" => "ListClusters") }
        assert_match "one of eu-west-1, us-east-1", error.message
      end

      test "a task definition's environment comes back as names, and a secret's value is never read" do
        AwsApi.any_instance.stubs(:call).with(:ecs, "us-east-1", :describe_task_definition, { task_definition: "web:3" })
              .returns(task_definition: { container_definitions: [ { name: "web", environment: [ { name: "DATABASE_URL", value: "postgres://u:pw@h/db" } ] } ] })

        shown = text(call("service" => "ecs", "operation" => "DescribeTaskDefinition", "params" => { "taskDefinition" => "web:3" }, "region" => "us-east-1"))
        assert_includes shown, "DATABASE_URL"
        assert_not_includes shown, "pw@h"
        assert_raises(PolicyRefusal) { call("service" => "secretsmanager", "operation" => "GetSecretValue", "params" => { "SecretId" => "x" }, "region" => "us-east-1") }
      end

      private

      def call(arguments) = @pack.call(ApiReads::TOOL, environment_row: @row, arguments: arguments)

      def text(result) = result["content"].map { |part| part["text"] }.join("\n")
    end
  end
end
