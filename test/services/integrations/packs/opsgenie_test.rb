require "test_helper"

module Integrations
  module Packs
    class OpsgenieTest < ActiveSupport::TestCase
      setup do
        @workspace = workspaces(:slack_workspace_one)
        @provider = IntegrationProvider.find(Providers::Opsgenie.key)
        @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: @provider.key, name: "Opsgenie",
                                           settings: { Integration::REGION_SETTING => OpsgenieApi::REGION_EU })
        @row = @integration.integration_environments.create!
        Opsgenie.store_credentials!(@row, Opsgenie::API_KEY => " og-key ")
        @pack = Opsgenie.new(@integration)
      end

      test "only acknowledging, escalating and adding a note change Opsgenie" do
        assert_equal %w[acknowledge_alert escalate_alert add_alert_note], Opsgenie.tool_definitions.reject(&:read_only).map(&:name)
      end

      test "the key is checked on the instance of the region chosen, and a key for the other one is said to be" do
        Http.expects(:request).with { |uri, *| uri.host == "api.eu.opsgenie.com" && uri.path == "/v2/account" }
            .returns(stub(code: "200", body: { data: { name: "acme" } }.to_json))
        assert_nil Opsgenie.credential_refusal({ Opsgenie::API_KEY => "og-key" }, region: @provider.region(OpsgenieApi::REGION_EU))

        OpsgenieApi.any_instance.stubs(:account).raises(OpsgenieApi::Unauthenticated, "Opsgenie answered 401: Could not authenticate")
        assert_equal "Opsgenie did not accept this key on its US (app.opsgenie.com) instance. Check the region, and that the API integration is turned on.",
                     Opsgenie.credential_refusal({ Opsgenie::API_KEY => "wrong" }, region: @provider.region(OpsgenieApi::REGION_US))
        assert_equal "Paste an API key.", Opsgenie.credential_refusal({ Opsgenie::API_KEY => " " }, region: nil)
        OpsgenieApi.any_instance.stubs(:account).raises(OpsgenieApi::Error, "Opsgenie answered 403: restricted")
        assert_equal "Opsgenie refused this key: Opsgenie answered 403: restricted.", Opsgenie.credential_refusal({ Opsgenie::API_KEY => "restricted" })
      end

      test "the regions are Opsgenie's two instances, and a call reaches the API of the connection's region with the stored key" do
        assert_equal [ OpsgenieApi::REGION_US, OpsgenieApi::REGION_EU ], @provider.regions.map(&:key)
        assert_equal OpsgenieApi::ROOTS.keys, @provider.regions.map(&:key)
        assert_equal "og-key", @row.reload.credentials_hash[Opsgenie::API_KEY]
        Http.expects(:request).with { |uri, request, **| uri.host == "api.eu.opsgenie.com" && request["Authorization"] == "GenieKey og-key" }
            .returns(stub(code: "200", body: { data: [] }.to_json))

        assert_equal "No Opsgenie alerts match.", call(:search_alerts)
      end

      test "who is on call names the people on each enabled schedule, with the team that owns it" do
        OpsgenieApi.any_instance.stubs(:schedules).returns([
          { "id" => "s1", "name" => "Platform", "enabled" => true, "ownerTeam" => { "name" => "ops_team" } },
          { "id" => "s2", "name" => "Old", "enabled" => false }
        ])
        OpsgenieApi.any_instance.expects(:on_calls).with("s1", by_name: false).returns("onCallRecipients" => [ "ana@acme.io" ])

        assert_equal "On call now in Opsgenie:\nPlatform (team ops_team): ana@acme.io", call(:who_is_on_call)
      end

      test "one schedule is asked for by name, or by id when it is one" do
        OpsgenieApi.any_instance.expects(:on_calls).with("Platform", by_name: true).returns("_parent" => { "name" => "Platform" }, "onCallRecipients" => [])

        assert_equal "Platform: nobody on call", call(:who_is_on_call, "schedule" => "Platform")
      end

      test "an alert reads in full with its details, notes and log" do
        OpsgenieApi.any_instance.stubs(:alert).with("1791", "tiny").returns(
          "id" => "70413a06", "tinyId" => "1791", "message" => "Our servers are in danger", "status" => "open", "acknowledged" => true,
          "priority" => "P1", "count" => 79, "createdAt" => "2026-10-04T08:00:00Z", "tags" => [ "Critical" ],
          "report" => { "ackTime" => 15_702, "acknowledgedBy" => "ana@acme.io" },
          "details" => { "region" => "Oregon" }
        )
        OpsgenieApi.any_instance.stubs(:alert_notes).returns([ { "note" => "Looking", "owner" => "ana@acme.io", "createdAt" => "2026-10-04T08:01:00Z" } ])
        OpsgenieApi.any_instance.stubs(:alert_logs).returns([ { "log" => "Alert acknowledged via web", "owner" => "ana@acme.io", "createdAt" => "2026-10-04T08:00:16Z" } ])

        text = call(:get_alert, "alert" => "1791", "identifier_type" => "tiny")

        assert text.start_with?("#1791 Our servers are in danger, id 70413a06, open, acknowledged by ana@acme.io, P1, fired 79 times")
        assert_includes text, "Acknowledged after 15 seconds by ana@acme.io"
        assert_includes text, "Notes, newest first:\n2026-10-04T08:01:00Z ana@acme.io: Looking"
        assert_includes text, "Log, newest first:\n2026-10-04T08:00:16Z ana@acme.io: Alert acknowledged via web"
        assert_includes text, "Details: region: Oregon"
        assert_raises(NativePack::Error) { call(:get_alert, "alert" => "1791", "identifier_type" => "number") }
      end

      test "an acknowledgement says it was done once Opsgenie says so" do
        OpsgenieApi.any_instance.expects(:acknowledge).with("70413a06", "id", note: "Halon is looking").returns("requestId" => "r1")
        OpsgenieApi.any_instance.stubs(:request_status).with("r1").returns("isSuccess" => true, "status" => "Acknowledged")

        assert_equal "Opsgenie did acknowledge alert 70413a06: Acknowledged.", call(:acknowledge_alert, "alert" => "70413a06", "note" => "Halon is looking")
      end

      test "an action Opsgenie could not do is an error with its reason, and one it has not finished says so" do
        @pack.stubs(:sleep)
        OpsgenieApi.any_instance.stubs(:add_note).returns("requestId" => "r2")
        OpsgenieApi.any_instance.stubs(:request_status).with("r2").returns("isSuccess" => false, "status" => "Alert does not exist")
        error = assert_raises(NativePack::Error) { call(:add_alert_note, "alert" => "gone", "note" => "Known") }
        assert_equal "Opsgenie could not add a note to alert gone: Alert does not exist.", error.message

        OpsgenieApi.any_instance.stubs(:escalate).returns("requestId" => "r3")
        OpsgenieApi.any_instance.stubs(:request_status).with("r3").raises(OpsgenieApi::Error, "Opsgenie answered 404: Request not found")
        assert_equal "Opsgenie accepted the request to escalate alert a1 to ops_escalation and has not said yet whether it is done. Check the alert with get_alert.",
                     call(:escalate_alert, "alert" => "a1", "escalation" => "ops_escalation")
      end

      test "the health check reads the account, and a connection without a key says to reconnect" do
        OpsgenieApi.any_instance.expects(:account).returns("name" => "acme")
        @pack.check_health!(@row)

        error = assert_raises(NativePack::Error) { Opsgenie.new(@integration).call("search_alerts", environment_row: IntegrationEnvironment.new(integration: @integration), arguments: {}) }
        assert_match "Reconnect it", error.message
      end

      private

      def call(tool, arguments = {})
        @pack.call(tool.to_s, environment_row: @row, arguments: arguments)
      end
    end
  end
end
