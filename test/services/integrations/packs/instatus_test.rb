require "test_helper"

module Integrations
  module Packs
    class InstatusTest < ActiveSupport::TestCase
      PAGE = { "id" => "pg1", "name" => "Acme", "subdomain" => "acme", "customDomain" => nil, "status" => "UP" }.freeze
      COMPONENTS = [
        { "id" => "c1", "name" => "API", "status" => "OPERATIONAL", "group" => { "id" => "g1", "name" => "Core" } },
        { "id" => "c2", "name" => "Checkout", "status" => "DEGRADEDPERFORMANCE", "group" => nil }
      ].freeze

      setup do
        @workspace = workspaces(:slack_workspace_one)
        @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: Providers::Instatus.key, name: "Instatus")
        @row = @integration.integration_environments.create!
        Instatus.store_credentials!(@row, Instatus::API_KEY => " in-key ")
        @pack = Instatus.new(@integration)
        InstatusApi.any_instance.stubs(:pages).returns(Pages::Read.new(items: [ PAGE ], complete: true))
        InstatusApi.any_instance.stubs(:components).returns(Pages::Read.new(items: COMPONENTS, complete: true))
        travel_to Time.utc(2026, 10, 14, 10, 0, 0)
      end

      test "the provider is a native status page host, and only the tools that read are read only" do
        entry = IntegrationProvider.find(Providers::Instatus.key)
        assert entry.holds_status_pages
        assert_equal Integration::KIND_NATIVE, entry.kind
        assert_equal %w[list_status_pages list_components get_component list_incidents get_incident list_maintenances get_maintenance list_subscribers list_templates],
                     Instatus.tool_definitions.select(&:read_only).map(&:name)
        assert_includes Instatus.tool_definitions.reject(&:read_only).map(&:name), "post_incident_update"
        assert_equal "in-key", @row.reload.credentials_hash[Instatus::API_KEY]
      end

      test "the key is checked by listing its pages before anything is saved" do
        assert_equal "Paste an API key.", Instatus.credential_refusal({ Instatus::API_KEY => "" })
        assert_nil Instatus.credential_refusal({ Instatus::API_KEY => "in-key" })
        InstatusApi.any_instance.stubs(:pages).raises(InstatusApi::Unauthenticated, "Instatus answered 401: API key does not belong to a user.")
        assert_equal "Instatus did not accept this key. Check it was copied whole from Developer settings.", Instatus.credential_refusal({ Instatus::API_KEY => "bad" })
      end

      test "a page is named by its subdomain, components read with their group, and the result links to the page on instatus.com" do
        result = call(:list_components, "page" => "acme")

        assert_includes text(result), "API (id c1), OPERATIONAL, group Core"
        assert_includes text(result), "https://acme.instatus.com"
        assert_equal "https://status.acme.io", InstatusApi.public_url(PAGE.merge("customDomain" => "status.acme.io"))
      end

      test "open incidents are the ones not resolved, and each links to its own page" do
        InstatusApi.any_instance.expects(:incidents).with("pg1", statuses: %w[INVESTIGATING IDENTIFIED MONITORING])
                   .returns(Pages::Read.new(items: [ { "id" => "i1", "name" => "Checkout down", "status" => "INVESTIGATING", "started" => "2026-10-14T09:00:00Z" } ], complete: true))
        assert_includes text(call(:list_incidents)), "Checkout down (id i1), INVESTIGATING, started 2026-10-14T09:00:00Z"

        InstatusApi.any_instance.stubs(:incident).returns("id" => "i1", "name" => "Checkout down", "status" => "INVESTIGATING",
                                                          "updates" => [ { "id" => "u1", "status" => "INVESTIGATING", "message" => "Looking", "started" => "2026-10-14T09:00:00Z" } ])
        result = call(:get_incident, "incident" => "i1")
        assert_includes text(result), "2026-10-14T09:00:00Z INVESTIGATING (update u1): Looking"
        assert_includes text(result), "https://acme.instatus.com/incident/i1"
      end

      test "opening an incident sets the components named and asks whether to tell subscribers" do
        error = assert_raises(NativePack::Error) { call(:create_incident, "name" => "Checkout down", "message" => "Looking") }
        assert_equal "Say whether to tell subscribers with notify, true or false. Ask the person which they want.", error.message

        InstatusApi.any_instance.expects(:create_incident).with("pg1", {
          "name" => "Checkout down", "message" => "Looking", "status" => "INVESTIGATING", "started" => "2026-10-14T10:00:00.000Z", "notify" => true,
          "components" => [ "c2" ], "statuses" => [ { "id" => "c2", "status" => "MAJOROUTAGE" } ]
        }).returns("id" => "i1", "name" => "Checkout down", "status" => "INVESTIGATING")

        result = call(:create_incident, "name" => "Checkout down", "message" => "Looking", "components" => { "Checkout" => "MAJOROUTAGE" }, "notify" => true)
        assert text(result).start_with?("Instatus opened incident Checkout down (id i1) on Acme, INVESTIGATING. Subscribers were told.")
        assert_raises(NativePack::Error) { call(:create_incident, "name" => "x", "message" => "y", "components" => { "API" => "DOWN" }, "notify" => true) }
      end

      test "an update is posted at its status and the incident is read back as customers now see it" do
        InstatusApi.any_instance.expects(:add_incident_update).with("pg1", "i1", {
          "message" => "Fixed", "status" => "RESOLVED", "started" => "2026-10-14T10:00:00.000Z", "notify" => false,
          "components" => [ "c2" ], "statuses" => [ { "id" => "c2", "status" => "OPERATIONAL" } ]
        }).returns("id" => "u2")
        InstatusApi.any_instance.stubs(:incident).returns("id" => "i1", "name" => "Checkout down", "status" => "RESOLVED")

        result = call(:post_incident_update, "incident" => "i1", "message" => "Fixed", "status" => "RESOLVED", "components" => { "c2" => "OPERATIONAL" }, "notify" => false)
        assert_includes text(result), "Instatus posted an update to Checkout down (id i1), now RESOLVED. Subscribers were not told."
        assert_raises(NativePack::Error) { call(:post_incident_update, "incident" => "i1", "message" => "x", "status" => "COMPLETED", "notify" => false) }
      end

      test "maintenance is scheduled for its window with its components under maintenance, and linked to its own page" do
        InstatusApi.any_instance.expects(:create_maintenance).with("pg1", {
          "name" => "Database upgrade", "message" => "Brief downtime", "status" => "NOTSTARTEDYET", "start" => "2026-10-20T22:00:00.000Z",
          "end" => "2026-10-20T23:30:00.000Z", "duration" => 90, "components" => [ "c1" ], "statuses" => [ { "id" => "c1", "status" => "UNDERMAINTENANCE" } ],
          "autoStart" => true, "autoEnd" => false, "notifyEarly" => true, "notifyMinutes" => 60, "notify" => true
        }).returns("id" => "m1", "name" => "Database upgrade", "status" => "NOTSTARTEDYET")

        result = call(:schedule_maintenance, "name" => "Database upgrade", "message" => "Brief downtime", "start" => "2026-10-20T22:00:00Z",
                                             "end" => "2026-10-20T23:30:00Z", "components" => [ "API" ], "auto_start" => true, "remind_minutes_before" => 60, "notify" => true)
        assert_includes text(result), "https://acme.instatus.com/maintenance/m1"
        assert_raises(NativePack::Error) do
          call(:schedule_maintenance, "name" => "x", "message" => "y", "start" => "2026-10-20T22:00:00Z", "end" => "2026-10-20T21:00:00Z", "notify" => true)
        end
      end

      test "a component's status is set by its name, and a subscriber added for every component when none is named" do
        InstatusApi.any_instance.expects(:update_component).with("pg1", "c2", { "status" => "MAJOROUTAGE" }).returns("name" => "Checkout", "status" => "MAJOROUTAGE")
        assert_includes text(call(:update_component, "component" => "checkout", "status" => "MAJOROUTAGE")), "Instatus changed Checkout on Acme, now MAJOROUTAGE."

        InstatusApi.any_instance.expects(:add_subscriber).with("pg1", { "email" => "ana@acme.io", "all" => true }).returns("id" => "s1")
        assert_includes text(call(:add_subscriber, "email" => "ana@acme.io")), "Instatus subscribed ana@acme.io (id s1) to Acme, for every component."
        assert_raises(NativePack::Error) { call(:add_subscriber, "name" => "Ana") }
      end

      test "a page is made with its first components, changed by the settings named, and deleted only when it is named" do
        InstatusApi.any_instance.expects(:create_page).with({ "name" => "Acme", "subdomain" => "acme2", "email" => "ops@acme.io", "components" => %w[API Web] })
                   .returns("id" => "pg2")
        assert_includes text(call(:create_status_page, "name" => "Acme", "subdomain" => "acme2", "email" => "ops@acme.io", "components" => %w[API Web])),
                        "Instatus made Acme (id pg2) with 2 components.\nOpen this in Instatus, on Acme, and give the person this link with what you found: https://acme2.instatus.com"

        InstatusApi.any_instance.expects(:update_page).with("pg1", { "name" => "Acme status", "private" => false, "subscriberConfirmationMode" => "REQUIRED" })
                   .returns("id" => "pg1", "name" => "Acme status", "subdomain" => "acme")
        assert_includes text(call(:update_status_page, "name" => "Acme status", "private" => false, "subscriber_confirmation" => "REQUIRED")),
                        "Instatus changed name, private and subscriber confirmation mode on Acme status."

        assert_raises(NativePack::Error) { call(:delete_status_page) }
        InstatusApi.any_instance.expects(:delete_page).with("pg1").returns("id" => "pg1")
        assert_equal "Instatus deleted the status page Acme (id pg1).", text(call(:delete_status_page, "page" => "Acme"))
      end

      private

      def call(tool, arguments = {}) = @pack.call(tool.to_s, environment_row: @row, arguments: arguments)

      def text(result) = result["content"].map { |part| part["text"] }.join("\n")
    end
  end
end
