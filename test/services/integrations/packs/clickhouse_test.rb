require "test_helper"

module Integrations
  module Packs
    class ClickhouseTest < ActiveSupport::TestCase
      ORGANIZATION = "11111111-1111-1111-1111-111111111111".freeze
      SERVICE = "22222222-2222-2222-2222-222222222222".freeze
      KEY = "Basic #{Base64.strict_encode64('key-id:key-secret')}".freeze
      BEFORE = { "name" => "analytics", "numReplicas" => 3, "minReplicaMemoryGb" => 16, "maxReplicaMemoryGb" => 64, "idleScaling" => true,
                 "idleTimeoutMinutes" => 15, "autoscalingMode" => "vertical" }.freeze

      setup do
        @integration = workspaces(:slack_workspace_one).integrations.create!(kind: Integration::KIND_MCP, provider: "clickhouse", name: "ClickHouse",
                                                                             settings: { "server_url" => "https://mcp.clickhouse.cloud/mcp" })
        @row = @integration.integration_environments.create!
        @pack = Clickhouse.new(@integration)
      end

      test "scaling reads the service, sends only what changes, and says how it scaled before and now" do
        Credentials.stubs(:headers_for).returns("Authorization" => KEY)
        ClickhouseApi.expects(:new).with(KEY).returns(api = mock("api"))
        api.expects(:service).with(ORGANIZATION, SERVICE).returns(BEFORE)
        api.expects(:replica_scaling).with(ORGANIZATION, SERVICE, { "numReplicas" => 5, "minReplicaMemoryGb" => 32, "maxReplicaMemoryGb" => 32 })
           .returns(BEFORE.merge("numReplicas" => 5, "minReplicaMemoryGb" => 32, "maxReplicaMemoryGb" => 32))

        text = scale("numReplicas" => 5, "minReplicaMemoryGb" => 32, "maxReplicaMemoryGb" => "32")

        assert_equal "ClickHouse Cloud changed how analytics scales.\nBefore: 3 replicas, 16 to 64 GiB each, scales to zero after 15 idle minutes.\n" \
                     "Now: 5 replicas, 32 GiB each, scales to zero after 15 idle minutes.", text
      end

      test "each value is checked against the API's limits before anything is sent" do
        Credentials.stubs(:headers_for).returns("Authorization" => KEY)
        ClickhouseApi.expects(:new).never

        assert_match "numReplicas is a whole number from 1 to 50", refusal("numReplicas" => 51)
        assert_match "a multiple of 4 from 8 to 356", refusal("minReplicaMemoryGb" => 10)
        assert_match "a multiple of 4 from 8 to 356", refusal("maxReplicaMemoryGb" => 360)
        assert_match "minReplicaMemoryGb cannot be more than maxReplicaMemoryGb", refusal("minReplicaMemoryGb" => 64, "maxReplicaMemoryGb" => 32)
        assert_match "5 or more", refusal("idleTimeoutMinutes" => 2)
        assert_match "Say what to change", refusal({})
      end

      test "a connection signed in rather than made with an API key is told how to reconnect, and a key without the permission is named" do
        Credentials.stubs(:headers_for).returns("Authorization" => "Bearer oauth-token")
        assert_match "Connect ClickHouse again with an API key whose role holds control-plane:service:manage-scaling-config", refusal("numReplicas" => 4)

        Credentials.stubs(:headers_for).returns("Authorization" => KEY)
        ClickhouseApi.any_instance.stubs(:service).raises(ClickhouseApi::Refused, "ClickHouse Cloud answered 403: Forbidden")
        assert_match "needs control-plane:service:manage-scaling-config", refusal("numReplicas" => 4)
      end

      test "a service that scales its replica count itself is not given a fixed count" do
        Credentials.stubs(:headers_for).returns("Authorization" => KEY)
        ClickhouseApi.any_instance.stubs(:service).returns(BEFORE.merge("autoscalingMode" => "horizontal", "minReplicas" => 2, "maxReplicas" => 6))
        ClickhouseApi.any_instance.expects(:replica_scaling).never

        assert_match "scales its replica count itself, between 2 and 6", refusal("numReplicas" => 4)
      end

      test "a stopped service is started, an idle one woken, and one already running is refused" do
        Credentials.stubs(:headers_for).returns("Authorization" => KEY)
        api = ClickhouseApi.new(KEY)
        ClickhouseApi.stubs(:new).returns(api)

        api.stubs(:service).returns(BEFORE.merge("state" => "stopped"))
        api.expects(:state).with(ORGANIZATION, SERVICE, "start").returns("state" => "starting")
        assert_equal "ClickHouse Cloud is starting analytics, which was stopped. It is starting now and takes queries once it is running.", act("start_service")

        api.stubs(:service).returns(BEFORE.merge("state" => "idle"))
        api.expects(:state).with(ORGANIZATION, SERVICE, "awake").returns("state" => "awaking")
        assert_match "is waking analytics, which was idle", act("start_service")

        api.stubs(:service).returns(BEFORE.merge("state" => "running"))
        assert_match "analytics is running, so there is nothing to start", assert_raises(NativePack::Error) { act("start_service") }.message
      end

      test "a running service is stopped, one already stopped is refused, and the permission a refused key lacks is named" do
        Credentials.stubs(:headers_for).returns("Authorization" => KEY)
        api = ClickhouseApi.new(KEY)
        ClickhouseApi.stubs(:new).returns(api)

        api.stubs(:service).returns(BEFORE.merge("state" => "running"))
        api.expects(:state).with(ORGANIZATION, SERVICE, "stop").returns("state" => "stopping")
        assert_match "is stopping analytics, which was running. It is stopping now, and every query to it fails until start_service", act("stop_service")

        api.stubs(:service).returns(BEFORE.merge("state" => "stopped"))
        assert_match "analytics is stopped, so there is nothing to stop", assert_raises(NativePack::Error) { act("stop_service") }.message

        api.stubs(:service).raises(ClickhouseApi::Refused, "ClickHouse Cloud answered 403: Forbidden")
        assert_match "needs control-plane:service:manage and control-plane:service:view", assert_raises(NativePack::Error) { act("stop_service") }.message

        Credentials.stubs(:headers_for).returns("Authorization" => "Bearer oauth-token")
        assert_match "To stop a service, Firefight goes through the ClickHouse Cloud API", assert_raises(NativePack::Error) { act("stop_service") }.message
      end

      test "a service's activities are its runs, a start or maintenance paired with what ended it, and another service's are left out" do
        Credentials.stubs(:headers_for).returns("Authorization" => KEY)
        listed = [
          activity("a1", "service_maintenance_start", "2026-10-10T10:00:00Z"), activity("a2", "service_maintenance_end", "2026-10-10T10:20:00Z"),
          activity("a3", "service_update_autoscaling_memory", "2026-10-11T09:00:00Z", "actorType" => "user", "actorDetails" => "ana@example.com"),
          activity("a4", "service_start", "2026-10-12T08:00:00Z"), activity("a5", "service_running", "2026-10-12T08:03:00Z"),
          activity("a6", "service_encryption_key_check_failed", "2026-10-13T08:00:00Z"), activity("a7", "service_awaken", "2026-10-14T08:00:00Z"),
          activity("a8", "service_stop", "2026-10-14T09:00:00Z", "serviceId" => "other")
        ]
        travel_to Time.utc(2026, 10, 20) do
          ClickhouseApi.any_instance.expects(:activities).with(ORGANIZATION, from: "2026-09-20T00:00:00Z", to: nil).returns(listed)
          result = @pack.call("activities", environment_row: @row, arguments: { "organizationId" => ORGANIZATION, "serviceId" => SERVICE })
          runs = Capabilities::History.runs_of(result)

          assert_equal [ %w[a7 awaken running], %w[a6 encryption_key_check_failed failed], %w[a4 start succeeded],
                         %w[a3 update_autoscaling_memory succeeded], %w[a1 maintenance_start succeeded] ],
                       runs.map { |run| [ run.id, run.name, run.status ] }
          assert_equal [ 180, 1200 ], [ runs[2].seconds, runs[4].seconds ]
          assert_equal "by user ana@example.com", runs[3].detail
        end
      end

      test "the organization's activities are listed newest first without a service, and a bad time is refused" do
        Credentials.stubs(:headers_for).returns("Authorization" => KEY)
        ClickhouseApi.any_instance.stubs(:activities).returns([ activity("a1", "key_create", "2026-10-10T10:00:00Z", "serviceId" => nil, "actorType" => "api"),
                                                                activity("a2", "user_login", "2026-10-11T10:00:00Z", "serviceId" => nil) ])
        text = @pack.call("activities", environment_row: @row, arguments: { "organizationId" => ORGANIZATION })

        assert_equal "The organization's latest 2 activities, newest first.\n2026-10-11T10:00:00Z, user login\n2026-10-10T10:00:00Z, key create, by api", text
        assert_match "ISO 8601", assert_raises(NativePack::Error) {
          @pack.call("activities", environment_row: @row, arguments: { "organizationId" => ORGANIZATION, "from" => "last week" })
        }.message
      end

      private

      def act(tool) = @pack.call(tool, environment_row: @row, arguments: { "organizationId" => ORGANIZATION, "serviceId" => SERVICE })

      def activity(id, type, at, extra = {}) = { "id" => id, "type" => type, "createdAt" => at, "serviceId" => SERVICE }.merge(extra)

      def scale(arguments)
        @pack.call("scale_service", environment_row: @row, arguments: { "organizationId" => ORGANIZATION, "serviceId" => SERVICE }.merge(arguments))
      end

      def refusal(arguments) = assert_raises(NativePack::Error) { scale(arguments) }.message
    end
  end
end
