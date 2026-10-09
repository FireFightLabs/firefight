require "test_helper"

module Integrations
  module MapEventSources
    class AwsTest < ActiveSupport::TestCase
      include LiveUpdatesTestHelper

      ACCOUNT = "123456789012".freeze
      KEY = "k" * 64
      SERVICE_ARN = "arn:aws:ecs:eu-west-1:#{ACCOUNT}:service/prod/web".freeze
      URL = "https://firefight.example.com/api/v1/map_events/token-1".freeze
      TEMPLATE = "https://firefight-templates.s3.us-east-1.amazonaws.com/aws-live-updates.json".freeze

      setup do
        @workspace = workspaces(:slack_workspace_one)
        @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "aws", name: "AWS")
        @row = @integration.integration_environments.create!
        Packs::Aws.store_credentials!(@row, Packs::Aws::ACCESS_KEY_ID => "AKIAEXAMPLE", Packs::Aws::SECRET_ACCESS_KEY => "secret")
        @row.store_fields!(Packs::Aws::REGIONS => %w[eu-west-1 us-east-1])
        Aws.stubs(:pause)
      end

      test "a delivery counts only with the connection's own key in its header" do
        assert Aws.verify(raw_body: "{}", headers: { Aws::KEY_HEADER => KEY }, secret: KEY)
        assert_not Aws.verify(raw_body: "{}", headers: { Aws::KEY_HEADER => "#{KEY}x" }, secret: KEY)
        assert_not Aws.verify(raw_body: "{}", headers: {}, secret: KEY)
        assert_not Aws.verify(raw_body: "{}", headers: { Aws::KEY_HEADER => "" }, secret: nil)
      end

      test "an API call names the resource it changed by ARN with CloudTrail's eventID, from EventBridge and from the event history alike" do
        record = update_service_record
        sent = Aws.events(api_call(record), headers: {}).sole
        read = Aws.record_events(JSON.parse(record.to_json)).sole

        assert_equal sent, read
        assert_equal [ "ev-1", ResourceMap::Event::UPDATED, Time.iso8601("2026-10-06T10:00:00Z") ], [ sent.id, sent.action, sent.at ]
        assert_equal ResourceMap::Scope.new(account: ACCOUNT, kind: Packs::Aws::SERVICE, external_id: SERVICE_ARN), sent.scope
      end

      test "each kind is named the way its calls record it, and a failed or unrelated call names nothing" do
        named = ->(source, name, asked: {}, answered: {}) { Aws.record_events(record(source, name, asked, answered)).map { |event| [ event.id, event.action, event.scope.external_id ] } }

        assert_equal [ [ "ev-1", ResourceMap::Event::ADDED, SERVICE_ARN ] ],
                     named.call(Aws::ECS, "CreateService", asked: { "cluster" => "arn:aws:ecs:eu-west-1:#{ACCOUNT}:cluster/prod", "serviceName" => "web" })
        assert_equal [ [ "ev-1", ResourceMap::Event::UPDATED, "arn:aws:ecs:eu-west-1:#{ACCOUNT}:service/default/web" ] ],
                     named.call(Aws::ECS, "UpdateService", asked: { "service" => "web" })
        assert_equal [ [ "ev-1", ResourceMap::Event::UPDATED, "arn:aws:lambda:eu-west-1:#{ACCOUNT}:function:checkout" ] ],
                     named.call(Aws::LAMBDA, "UpdateFunctionCode20150331v2", asked: { "functionName" => "checkout" })
        assert_equal [ [ "ev-1", ResourceMap::Event::REMOVED, "arn:aws:lambda:eu-west-1:#{ACCOUNT}:function:checkout" ] ],
                     named.call(Aws::LAMBDA, "DeleteFunction20150331", asked: { "functionName" => "arn:aws:lambda:eu-west-1:#{ACCOUNT}:function:checkout:7" })
        instances = { "instancesSet" => { "items" => [ { "instanceId" => "i-1" }, { "instanceId" => "i-2" } ] } }
        assert_equal [ [ "ev-1 arn:aws:ec2:eu-west-1:#{ACCOUNT}:instance/i-1", ResourceMap::Event::ADDED, "arn:aws:ec2:eu-west-1:#{ACCOUNT}:instance/i-1" ],
                       [ "ev-1 arn:aws:ec2:eu-west-1:#{ACCOUNT}:instance/i-2", ResourceMap::Event::ADDED, "arn:aws:ec2:eu-west-1:#{ACCOUNT}:instance/i-2" ] ],
                     named.call(Aws::EC2, "RunInstances", answered: instances), "one call starting two instances is two changes, each kept once"
        assert_equal [ "arn:aws:ec2:eu-west-1:#{ACCOUNT}:instance/i-1" ],
                     named.call(Aws::EC2, "CreateTags", asked: { "resourcesSet" => { "items" => [ { "resourceId" => "i-1" }, { "resourceId" => "vol-1" } ] } }).map(&:last)
        assert_equal [ "arn:aws:rds:eu-west-1:#{ACCOUNT}:db:orders", "arn:aws:rds:eu-west-1:#{ACCOUNT}:db:orders-2" ],
                     named.call(Aws::RDS, "ModifyDBInstance", asked: { "dBInstanceIdentifier" => "Orders", "newDBInstanceIdentifier" => "orders-2" }).map(&:last)
        assert_empty named.call(Aws::EC2, "AuthorizeSecurityGroupIngress", asked: { "groupId" => "sg-1" })
        assert_empty Aws.record_events(record(Aws::ECS, "UpdateService", { "service" => "web" }, {}).merge("errorCode" => "AccessDeniedException"))
      end

      test "state changes name an instance, a service or a database, and the stack's own status names nothing" do
        terminated = Aws.events(state("EC2 Instance State-change Notification", "detail" => { "instance-id" => "i-1", "state" => "terminated" }), headers: {}).sole
        assert_equal [ "eb-1", ResourceMap::Event::REMOVED, "arn:aws:ec2:eu-west-1:#{ACCOUNT}:instance/i-1" ], [ terminated.id, terminated.action, terminated.scope.external_id ]

        deployed = Aws.events(state("ECS Deployment State Change", "resources" => [ SERVICE_ARN ], "detail" => { "eventName" => "SERVICE_DEPLOYMENT_FAILED" }), headers: {}).sole
        assert_equal [ Packs::Aws::SERVICE, SERVICE_ARN ], [ deployed.scope.kind, deployed.scope.external_id ]

        database = "arn:aws:rds:eu-west-1:#{ACCOUNT}:db:orders"
        stopped = Aws.events(state("RDS DB Instance Event", "detail" => { "SourceType" => "DB_INSTANCE", "SourceArn" => database }), headers: {}).sole
        assert_equal [ Packs::Aws::DATABASE, database ], [ stopped.scope.kind, stopped.scope.external_id ]
        assert_empty Aws.events(state("RDS DB Instance Event", "detail" => { "SourceType" => "SNAPSHOT", "SourceArn" => "arn:aws:rds:eu-west-1:#{ACCOUNT}:snapshot:s" }), headers: {})

        deleting = state(Aws::STACK_STATUS, "detail" => { "status-details" => { "status" => "DELETE_IN_PROGRESS" } })
        assert_empty Aws.events(deleting, headers: {})
        assert Aws.delivery_ends?(deleting)
        assert_not Aws.delivery_ends?(state(Aws::STACK_STATUS, "detail" => { "status-details" => { "status" => "CREATE_COMPLETE" } }))
        assert_equal "eu-west-1", Aws.delivery_place(deleting)
      end

      test "the event history is read from where the last read ended, writes only, at most two lookups a second per region" do
        travel_to Time.zone.parse("2026-10-06 10:00:00 UTC")
        AwsApi.any_instance.expects(:call).never
        first = Aws.poll(@row, since: nil)
        assert_empty first.events
        assert_equal %w[eu-west-1 us-east-1], JSON.parse(first.cursor).keys, "a region read for the first time starts now"

        travel 5.minutes
        record = update_service_record
        AwsApi.any_instance.unstub(:call)
        AwsApi.any_instance.expects(:call).with(:cloudtrail, "eu-west-1", :lookup_events, has_entries(start_time: Time.zone.parse("2026-10-06 09:45:00 UTC"), lookup_attributes: [ Aws::WRITES ]))
              .returns(events: [ { event_id: "ev-1", event_source: Aws::ECS, cloud_trail_event: record.to_json } ], next_token: "page-2")
        AwsApi.any_instance.expects(:call).with(:cloudtrail, "eu-west-1", :lookup_events, has_entries(next_token: "page-2"))
              .returns(events: [ { event_id: "ev-9", event_source: "s3.amazonaws.com", cloud_trail_event: "{}" } ])
        AwsApi.any_instance.expects(:call).with(:cloudtrail, "us-east-1", :lookup_events, anything).returns(events: [])
        Aws.expects(:pause).with(Aws::LOOKUP_INTERVAL).once

        second = Aws.poll(@row, since: first.cursor)

        assert_equal [ "ev-1" ], second.events.map(&:id)
        assert_equal [ Time.current.utc.iso8601(6) ] * 2, JSON.parse(second.cursor).values
      end

      test "a region AWS asks to slow down keeps its place, a busy one is swept in full, and keys without the permission say which" do
        since = { "eu-west-1" => 10.minutes.ago.utc.iso8601(6), "us-east-1" => 10.minutes.ago.utc.iso8601(6) }.to_json
        AwsApi.any_instance.stubs(:call).with(:cloudtrail, "eu-west-1", :lookup_events, anything).raises(AwsApi::RateLimited, "AWS answered ThrottlingException: Rate exceeded")
        AwsApi.any_instance.stubs(:call).with(:cloudtrail, "us-east-1", :lookup_events, anything).returns(events: [], next_token: "more")

        polled = Aws.poll(@row, since: since)

        assert_equal JSON.parse(since)["eu-west-1"], JSON.parse(polled.cursor)["eu-west-1"]
        assert_predicate polled.events.sole.scope, :everything?

        AwsApi.any_instance.stubs(:call).with(:cloudtrail, "eu-west-1", :lookup_events, anything).raises(AwsApi::Denied, "AWS answered AccessDeniedException: not authorized to perform cloudtrail:LookupEvents")
        AwsApi.any_instance.stubs(:call).with(:cloudtrail, "us-east-1", :lookup_events, anything).raises(AwsApi::Denied, "AWS answered AccessDeniedException: not authorized to perform cloudtrail:LookupEvents")
        error = assert_raises(Integrations::Error) { Aws.poll(@row, since: since) }
        assert_equal "#{Aws::DENIED}. AWS answered AccessDeniedException: not authorized to perform cloudtrail:LookupEvents.", error.message
      end

      test "a region that refuses keeps its place and says so, while the other regions are still read" do
        travel_to Time.zone.parse("2026-10-06 10:00:00 UTC")
        since = { "eu-west-1" => 10.minutes.ago.utc.iso8601(6), "us-east-1" => 10.minutes.ago.utc.iso8601(6) }.to_json
        AwsApi.any_instance.stubs(:call).with(:cloudtrail, "eu-west-1", :lookup_events, anything)
              .raises(AwsApi::Denied, "AWS answered UnrecognizedClientException: The security token included in the request is invalid")
        AwsApi.any_instance.stubs(:call).with(:cloudtrail, "us-east-1", :lookup_events, anything)
              .returns(events: [ { event_id: "ev-1", event_source: Aws::ECS, cloud_trail_event: update_service_record.to_json } ])

        polled = Aws.poll(@row, since: since)

        assert_equal [ "ev-1" ], polled.events.map(&:id)
        assert_equal JSON.parse(since)["eu-west-1"], JSON.parse(polled.cursor)["eu-west-1"]
        assert_equal Time.current.utc.iso8601(6), JSON.parse(polled.cursor)["us-east-1"]
        assert_equal "CloudTrail in eu-west-1 could not be read: AWS answered UnrecognizedClientException: The security token included in the request is invalid.", polled.error

        AwsApi.any_instance.stubs(:call).with(:cloudtrail, "eu-west-1", :lookup_events, anything).raises(AwsApi::Error, "AWS could not be reached: timed out")
        assert_equal "CloudTrail in eu-west-1 could not be read: AWS could not be reached: timed out.", Aws.poll(@row, since: since).error
      end

      test "each connected region offers a quick-create link with the connection's address and key, once the template is published" do
        with_template(nil) { assert_equal Aws::UNPUBLISHED, Aws.offer_unavailable_reason }
        with_template("https://example.com/template.json") { assert_equal Aws::UNPUBLISHED, Aws.offer_unavailable_reason, "a quick-create link takes a template only from S3" }

        assert_equal [ [ "eu-west-1", "Europe (Ireland)", nil ], [ "us-east-1", "US East (N. Virginia)", nil ] ],
                     Aws.offers(@row).map { |offer| [ offer.place, offer.label, offer.unavailable ] }
        link = with_template(TEMPLATE) do
          assert_nil Aws.offer_unavailable_reason
          Aws.offer_link(@row, place: "eu-west-1", url: URL, secret: KEY)
        end
        base, fragment = link.split("#", 2)
        assert_equal "https://eu-west-1.console.aws.amazon.com/cloudformation/home?region=eu-west-1", base
        query = Rack::Utils.parse_query(fragment.delete_prefix("/stacks/create/review?"))
        assert_equal({ "templateURL" => TEMPLATE, "stackName" => Aws.stack_name(@row), "param_Address" => URL, "param_Key" => KEY }, query)
        assert_match(/\Afirefight-live-updates-\h{8}\z/, Aws.stack_name(@row))
        assert_equal "To stop, delete the CloudFormation stack #{Aws.stack_name(@row)} in eu-west-1 and us-east-1. Firefight did not create it, so it cannot remove it.",
                     Aws.removal_words(@row, %w[eu-west-1 us-east-1])
      end

      test "a region where EventBridge has no API destinations offers no stack and says why" do
        @row.store_fields!(Packs::Aws::REGIONS => %w[eu-west-1 ca-west-1])

        assert_equal [ nil, Aws::NO_API_DESTINATIONS ], Aws.offers(@row).map(&:unavailable)
        with_template(TEMPLATE) { assert_equal Aws::NO_API_DESTINATIONS, @row.live_updates_setup_blocked_reason("ca-west-1") }
      end

      test "the template asks EventBridge for what the source reads, with the key in the header Firefight checks" do
        template = Aws.template
        resources = template["Resources"]

        assert_equal %w[AWS::Events::ApiDestination AWS::Events::Connection AWS::Events::Rule AWS::IAM::Role], resources.values.map { |each| each["Type"] }.uniq.sort
        assert_equal %w[Address Key], template["Parameters"].keys
        assert_equal Aws::KEY_HEADER, resources.dig("FirefightConnection", "Properties", "AuthParameters", "ApiKeyAuthParameters", "ApiKeyName")
        calls = resources.dig("FirefightApiCalls", "Properties", "EventPattern", "detail")
        assert_equal Aws::CALLS.keys.sort, calls["eventSource"].sort
        asked = calls["eventName"].map { |name| name.is_a?(Hash) ? name["prefix"] : name }
        assert_equal Aws::CALLS.values.flatten.uniq.sort, asked.uniq.sort
        states = resources.dig("FirefightStateChanges", "Properties", "EventPattern", "detail-type")
        assert_equal [ Aws::EC2_STATE, *Aws::ECS_SERVICE, Aws::RDS_INSTANCE ].sort, states.sort
        assert_equal [ Aws::STACK_STATUS ], resources.dig("FirefightStackStatus", "Properties", "EventPattern", "detail-type")
        assert(resources.values.select { |each| each["Type"] == "AWS::Events::Rule" }.all? { |rule| rule.dig("Properties", "State") == "ENABLED" })
      end

      private

      def update_service_record
        record(Aws::ECS, "UpdateService", { "cluster" => "prod", "service" => "web" }, { "service" => { "serviceArn" => SERVICE_ARN } })
      end

      def record(source, name, asked, answered)
        { "eventID" => "ev-1", "eventTime" => "2026-10-06T10:00:00Z", "eventSource" => source, "eventName" => name, "awsRegion" => "eu-west-1",
          "recipientAccountId" => ACCOUNT, "requestParameters" => asked, "responseElements" => answered }
      end

      def api_call(record)
        { "id" => "eb-9", "detail-type" => Aws::API_CALL, "source" => "aws.ecs", "account" => ACCOUNT, "time" => "2026-10-06T10:00:05Z",
          "region" => "eu-west-1", "resources" => [], "detail" => record }
      end

      def state(type, extra)
        { "id" => "eb-1", "detail-type" => type, "account" => ACCOUNT, "time" => "2026-10-06T10:00:00Z", "region" => "eu-west-1", "resources" => [] }.merge(extra)
      end

      def with_template(url)
        previous = ENV[Aws::TEMPLATE_URL]
        ENV[Aws::TEMPLATE_URL] = url
        yield
      ensure
        ENV[Aws::TEMPLATE_URL] = previous
      end
    end
  end
end
