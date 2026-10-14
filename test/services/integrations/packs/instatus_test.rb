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
        assert_equal %w[list_status_pages list_components get_component list_incidents get_incident list_maintenances get_maintenance list_subscribers list_templates
                        list_monitors get_monitor_logs list_monitor_alerts list_cron_monitors get_cron_monitor list_metrics get_metric list_notices list_outages list_teammates],
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

      test "an incident from a template is opened with the template's words and components, telling subscribers only as the person chose" do
        template = { "id" => "t1", "type" => "INCIDENT", "name" => "Website down", "message" => "Investigating", "status" => "INVESTIGATING", "notify" => true,
                     "components" => [ { "id" => "c1", "status" => "MAJOROUTAGE" } ] }
        InstatusApi.any_instance.stubs(:template).with("pg1", "t1").returns(template)
        assert_raises(NativePack::Error) { call(:create_incident_from_template, "template" => "t1") }

        InstatusApi.any_instance.expects(:create_incident_from_template).never
        InstatusApi.any_instance.expects(:create_incident).with("pg1", {
          "name" => "Website down", "message" => "Investigating", "status" => "INVESTIGATING", "started" => "2026-10-14T10:00:00.000Z", "notify" => false,
          "components" => [ "c1" ], "statuses" => [ { "id" => "c1", "status" => "MAJOROUTAGE" } ]
        }).returns("id" => "i3", "name" => "Website down", "status" => "INVESTIGATING")

        assert_includes text(call(:create_incident_from_template, "template" => "t1", "notify" => false)), "Subscribers were not told."
        InstatusApi.any_instance.stubs(:template).with("pg1", "m1").returns(template.merge("id" => "m1", "type" => "MAINTENANCE"))
        assert_raises(NativePack::Error) { call(:create_incident_from_template, "template" => "m1", "notify" => true) }
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

      test "a component is put in a group by name, sent as group on create and groupId on change, and the other name is tried when it did not land" do
        InstatusApi.any_instance.expects(:create_component).with("pg1", { "name" => "Search", "status" => "OPERATIONAL", "grouped" => true, "group" => "g1" })
                   .returns("id" => "c3", "name" => "Search", "group" => { "id" => "g1", "name" => "Core" })
        call(:create_component, "name" => "Search", "group" => "Core")

        InstatusApi.any_instance.expects(:update_component).with("pg1", "c2", { "grouped" => true, "groupId" => "g1" }).returns("id" => "c2", "group" => nil)
        InstatusApi.any_instance.expects(:update_component).with("pg1", "c2", { "grouped" => true, "group" => "g1" })
                   .returns("id" => "c2", "name" => "Checkout", "status" => "DEGRADEDPERFORMANCE", "group" => { "id" => "g1" })
        call(:update_component, "component" => "Checkout", "group" => "g1")

        InstatusApi.any_instance.expects(:update_component).with("pg1", "c1", { "grouped" => false }).twice.returns("id" => "c1", "group" => { "id" => "g1" })
        error = assert_raises(NativePack::Error) { call(:update_component, "component" => "API", "group" => "none") }
        assert_equal "Instatus took the change but did not take it out of its group. Check it in Instatus.", error.message
        assert_raises(NativePack::Error) { call(:update_component, "component" => "API", "group" => "Edge") }
      end

      test "a component made without its id and outside its group is said in words, never moved at an empty address" do
        InstatusApi.any_instance.expects(:create_component).returns("name" => "Search", "group" => nil)
        InstatusApi.any_instance.expects(:update_component).never

        error = assert_raises(NativePack::Error) { call(:create_component, "name" => "Search", "group" => "Core") }
        assert_equal "Instatus added Search but did not return its id, so it was not put in group g1. Check it in Instatus.", error.message
      end

      test "an alert's recipient is an email or a phone number, never a webhook address, made or changed" do
        assert_raises(Integrations::PolicyRefusal) { call(:update_monitor_alert, "alert" => "a1", "recipient" => "https://hooks.slack.com/services/x") }
        assert_raises(Integrations::PolicyRefusal) { call(:create_monitor_alert, "type" => "EMAIL", "recipient" => "https://hook.acme.io/x", "monitors" => [ "m1" ]) }

        InstatusApi.any_instance.expects(:update_monitor_alert).with("a1", { "recipient" => "+44 20 7946 0958" }).returns({})
        call(:update_monitor_alert, "alert" => "a1", "recipient" => "+44 20 7946 0958")
        InstatusApi.any_instance.expects(:update_monitor_alert).with("a1", { "recipient" => "ops@acme.io" }).returns({})
        call(:update_monitor_alert, "alert" => "a1", "recipient" => "ops@acme.io")
      end

      test "a page's look is set with its other settings, and its SMS provider's credentials cannot be sent" do
        InstatusApi.any_instance.expects(:update_page).with("pg1", { "brandColor" => "#111111", "cssGlobal" => "body { margin: 0 }", "useLargeHeader" => false })
                   .returns("id" => "pg1", "name" => "Acme", "subdomain" => "acme")
        call(:update_status_page, "brand_color" => "#111111", "css_global" => "body { margin: 0 }", "use_large_header" => false)

        properties = Instatus.tool_definitions.find { |each| each.name == "update_status_page" }.params_schema["properties"].keys
        assert_empty properties.grep(/twilio|esendex|nexmo|sms_service/)
      end

      test "a monitor never takes a credential, an alert never a webhook, and a cron monitor's ping address is never shown" do
        error = assert_raises(Integrations::PolicyRefusal) do
          call(:create_monitor, "name" => "API", "url" => "https://api.acme.io", "headers" => { "Authorization" => "Bearer x" })
        end
        assert_includes error.message, "Authorization"
        assert_raises(Integrations::PolicyRefusal) { call(:create_monitor_alert, "type" => "SLACK", "recipient" => "https://hooks.slack.com/x", "monitors" => [ "m1" ]) }

        InstatusApi.any_instance.expects(:create_monitor).with({
          "name" => "API", "url" => "https://api.acme.io", "httpMethod" => "GET", "headers" => { "Accept" => "application/json" }, "checksInterval" => 60,
          "onFail" => { "createIncident" => true, "notifySubscribers" => false }, "pageId" => "pg1", "type" => "HTTP"
        }).returns("monitor" => { "id" => "m1", "name" => "API" })
        assert_includes text(call(:create_monitor, "name" => "API", "url" => "https://api.acme.io", "headers" => { "Accept" => "application/json" }, "checks_interval" => 60,
                                                   "on_fail" => { "create_incident" => true, "notify_subscribers" => false })),
                        "Instatus started monitor API (id m1) checking https://api.acme.io on Acme."

        InstatusApi.any_instance.stubs(:cron_monitors).returns(Pages::Read.new(items: [ { "id" => "k1", "name" => "Backup", "slug" => "acme-secret-slug", "period" => 86_400,
                                                                                         "status" => "UP", "state" => "ACTIVE" } ], complete: true))
        listed = text(call(:list_cron_monitors))
        assert_includes listed, "Backup (id k1), UP, ACTIVE, every 86400 seconds"
        assert_not_includes listed, "acme-secret-slug"

        InstatusApi.any_instance.stubs(:monitor_alerts).returns(Pages::Read.new(items: [ { "id" => "a1", "type" => "WEBHOOK", "recipient" => "https://hook.acme.io/s3cret", "monitors" => [] },
                                                                                          { "id" => "a2", "type" => "EMAIL", "recipient" => "ops@acme.io", "whenFails" => true, "monitors" => [ { "id" => "m1" } ] } ],
                                                                                 complete: true))
        alerts = text(call(:list_monitor_alerts))
        assert_not_includes alerts, "s3cret"
        assert_includes alerts, "EMAIL (id a2), to ops@acme.io, on fails, 1 monitors"
      end

      test "notices ask whether to tell subscribers, outages are recorded on a component, metrics take readings in milliseconds, and teammates are named by email" do
        assert_raises(NativePack::Error) { call(:create_notice, "name" => "DNS move") }
        InstatusApi.any_instance.expects(:create_notice).with("pg1", { "name" => "DNS move", "notify" => false, "isCollapsed" => false }).returns("id" => "n1")
        assert_includes text(call(:create_notice, "name" => "DNS move", "notify" => false)), "Subscribers were not told."

        InstatusApi.any_instance.expects(:create_outage).with("pg1", { "status" => "PARTIALOUTAGE", "from" => "2026-10-14T08:00:00.000Z", "componentId" => "c2" }).returns("id" => "o1")
        call(:create_outage, "component" => "Checkout", "status" => "PARTIALOUTAGE", "from" => "2026-10-14T08:00:00Z")
        assert_raises(NativePack::Error) { call(:create_outage, "component" => "Checkout", "status" => "OPERATIONAL", "from" => "2026-10-14T08:00:00Z") }

        InstatusApi.any_instance.stubs(:metrics).returns(Pages::Read.new(items: [ { "id" => "x1", "name" => { "default" => "Latency" }, "suffix" => "ms" } ], complete: true))
        InstatusApi.any_instance.expects(:add_metric_data).with("pg1", "x1", [ { "timestamp" => 1_791_936_000_000, "value" => 120 } ]).returns([])
        call(:add_metric_data, "metric" => "latency", "points" => [ { "at" => "2026-10-14T00:00:00Z", "value" => 120 } ])

        InstatusApi.any_instance.stubs(:teammates).returns(Pages::Read.new(items: [ { "id" => "t1", "user" => { "email" => "bo@acme.io", "name" => "Bo" } } ], complete: true))
        InstatusApi.any_instance.expects(:remove_teammate).with("pg1", "t1").returns("memberId" => "t1")
        assert_includes text(call(:remove_teammate, "member" => "bo@acme.io")), "Instatus took away bo@acme.io's access to manage Acme."
      end

      private

      def call(tool, arguments = {}) = @pack.call(tool.to_s, environment_row: @row, arguments: arguments)

      def text(result) = result["content"].map { |part| part["text"] }.join("\n")
    end
  end
end
