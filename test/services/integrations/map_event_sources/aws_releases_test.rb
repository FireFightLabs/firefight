require "test_helper"

module Integrations
  module MapEventSources
    # Payloads in the shapes CodePipeline's, CodeDeploy's, App Runner's and Elastic Beanstalk's EventBridge guides give,
    # and CloudTrail records of the calls each service's CloudTrail page names.
    class AwsReleasesTest < ActiveSupport::TestCase
      ACCOUNT = "123456789012".freeze
      PIPELINE_ARN = "arn:aws:codepipeline:eu-west-1:#{ACCOUNT}:release-web".freeze
      STACK_ARN = "arn:aws:cloudformation:eu-west-1:#{ACCOUNT}:stack/shop-infra/5b2c8e10".freeze
      APP_ARN = "arn:aws:apprunner:eu-west-1:#{ACCOUNT}:service/api/8fe1e103".freeze

      test "a release changing state names its pipeline, deployment group, stack, service or environment" do
        action = scope_of("CodePipeline Action Execution State Change", "resources" => [ PIPELINE_ARN ], "detail" => { "pipeline" => "release-web", "state" => "FAILED" })
        assert_equal [ ResourceMap::KIND_PIPELINE, PIPELINE_ARN ], action

        deployment = scope_of(Aws::DEPLOYMENT_STATE, "detail" => { "application" => "shop", "deploymentGroup" => "web-prod", "deploymentId" => "d-ABCDEF123", "state" => "FAILURE" })
        assert_equal [ ResourceMap::KIND_RELEASE_FLOW, "arn:aws:codedeploy:eu-west-1:#{ACCOUNT}:deploymentgroup:shop/web-prod" ], deployment

        assert_equal [ ResourceMap::KIND_STACK, STACK_ARN ],
                     scope_of(Aws::STACK_STATUS, "detail" => { "stack-id" => STACK_ARN, "status-details" => { "status" => "UPDATE_ROLLBACK_COMPLETE" } })
        deleted = Aws.events(payload(Aws::STACK_STATUS, "detail" => { "stack-id" => STACK_ARN, "status-details" => { "status" => "DELETE_COMPLETE" } }), headers: {}).sole
        assert_equal ResourceMap::Event::REMOVED, deleted.action
        own = payload(Aws::STACK_STATUS, "detail" => { "stack-id" => "arn:aws:cloudformation:eu-west-1:#{ACCOUNT}:stack/firefight-live-updates-0a1b2c3d/7f0e",
                                                       "status-details" => { "status" => "DELETE_IN_PROGRESS" } })
        assert_empty Aws.events(own, headers: {}), "Firefight's own stack says only whether its region sends changes"
        team = payload(Aws::STACK_STATUS, "detail" => { "stack-id" => STACK_ARN, "status-details" => { "status" => "DELETE_IN_PROGRESS" } })
        assert_not Aws.delivery_ends?(team), "a team's stack being deleted does not end the region's live updates"

        assert_equal [ ResourceMap::KIND_SERVICE, APP_ARN ],
                     scope_of("AppRunner Service Operation Status Change", "resources" => [ APP_ARN ], "detail" => { "operationStatus" => "DeploymentFailed" })
        assert_equal [ ResourceMap::KIND_SERVICE, "arn:aws:elasticbeanstalk:eu-west-1:#{ACCOUNT}:environment/shop/shop-prod" ],
                     scope_of("Elastic Beanstalk resource status change", "detail" => { "Status" => "Environment update failed", "ApplicationName" => "shop", "EnvironmentName" => "shop-prod" })
      end

      test "a call that starts, stops or rolls back a release names what it runs in, and a stack named only by its name is left to the sweep" do
        assert_equal [ [ ResourceMap::KIND_PIPELINE, PIPELINE_ARN, ResourceMap::Event::UPDATED ] ],
                     named(Aws::CODEPIPELINE, "StartPipelineExecution", { "name" => "release-web" })
        assert_equal [ [ ResourceMap::KIND_PIPELINE, PIPELINE_ARN, ResourceMap::Event::REMOVED ] ], named(Aws::CODEPIPELINE, "DeletePipeline", { "name" => "release-web" })
        renamed = named(Aws::CODEDEPLOY, "UpdateDeploymentGroup", { "applicationName" => "shop", "currentDeploymentGroupName" => "web", "newDeploymentGroupName" => "web-prod" })
        assert_equal %w[web web-prod], renamed.map { |(_, arn, _)| arn.split("/").last }
        assert_equal [ [ ResourceMap::KIND_STACK, STACK_ARN, ResourceMap::Event::UPDATED ] ], named(Aws::CLOUDFORMATION, "UpdateStack", { "stackName" => "shop-infra" }, { "stackId" => STACK_ARN })
        assert_empty named(Aws::CLOUDFORMATION, "CancelUpdateStack", { "stackName" => "shop-infra" })
        assert_equal [ [ ResourceMap::KIND_SERVICE, APP_ARN, ResourceMap::Event::UPDATED ] ], named(Aws::APPRUNNER, "StartDeployment", { "serviceArn" => APP_ARN })
        environment = named(Aws::BEANSTALK, "UpdateEnvironment", { "environmentName" => "shop-prod" },
                            { "environmentArn" => "arn:aws:elasticbeanstalk:eu-west-1:#{ACCOUNT}:environment/shop/shop-prod" })
        assert_equal [ ResourceMap::KIND_SERVICE, ResourceMap::Event::UPDATED ], environment.sole.values_at(0, 2)
        assert_empty named(Aws::CODEDEPLOY, "StopDeployment", { "deploymentId" => "d-ABCDEF123" }), "a call that names no group is not read"
      end

      private

      def payload(type, extra)
        { "id" => "eb-1", "detail-type" => type, "account" => ACCOUNT, "time" => "2026-10-06T10:00:00Z", "region" => "eu-west-1", "resources" => [] }.merge(extra)
      end

      def scope_of(type, extra)
        Aws.events(payload(type, extra), headers: {}).sole.scope.then { |scope| [ scope.kind, scope.external_id ] }
      end

      def named(source, name, asked, answered = {})
        record = { "eventID" => "ev-1", "eventTime" => "2026-10-06T10:00:00Z", "eventSource" => source, "eventName" => name, "awsRegion" => "eu-west-1",
                   "recipientAccountId" => ACCOUNT, "requestParameters" => asked, "responseElements" => answered }
        Aws.record_events(record).map { |event| [ event.scope.kind, event.scope.external_id, event.action ] }
      end
    end
  end
end
