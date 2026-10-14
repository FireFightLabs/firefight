require "test_helper"

module Integrations
  module Packs
    class StatuspageTest < ActiveSupport::TestCase
      PAGE = { "id" => "pg1", "name" => "Acme", "subdomain" => "acme", "domain" => "status.acme.io", "allow_email_subscribers" => true }.freeze
      COMPONENTS = [
        { "id" => "c1", "name" => "API", "status" => "operational", "group" => false, "group_id" => "g1" },
        { "id" => "c2", "name" => "Checkout", "status" => "degraded_performance", "group" => false, "group_id" => nil },
        { "id" => "g1", "name" => "Core", "status" => "operational", "group" => true, "group_id" => nil }
      ].freeze

      setup do
        @workspace = workspaces(:slack_workspace_one)
        @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: Providers::Statuspage.key, name: "Statuspage")
        @row = @integration.integration_environments.create!
        Statuspage.store_credentials!(@row, Statuspage::API_KEY => " sp-key ")
        @pack = Statuspage.new(@integration)
        StatuspageApi.any_instance.stubs(:pages).returns(Pages::Read.new(items: [ PAGE ], complete: true))
        StatuspageApi.any_instance.stubs(:components).returns(Pages::Read.new(items: COMPONENTS, complete: true))
      end

      test "the provider is a native status page host its tools are read from, and only the tools that read are read only" do
        entry = IntegrationProvider.find(Providers::Statuspage.key)
        assert entry.holds_status_pages
        assert_equal Integration::KIND_NATIVE, entry.kind
        assert_equal %w[list_pages list_components get_component_uptime list_incidents get_incident get_postmortem list_incident_templates
                        list_subscribers count_subscribers list_incident_subscribers get_status_embed list_unsubscribed subscriber_histogram
                        list_metrics_providers list_metrics list_page_access_users list_page_access_groups], Statuspage.tool_definitions.select(&:read_only).map(&:name)
        assert_includes Statuspage.tool_definitions.reject(&:read_only).map(&:name), "post_incident_update"
        assert_equal "sp-key", @row.reload.credentials_hash[Statuspage::API_KEY]
      end

      test "the key is checked by listing its pages before anything is saved" do
        assert_equal "Paste an API key.", Statuspage.credential_refusal({ Statuspage::API_KEY => " " })
        assert_nil Statuspage.credential_refusal({ Statuspage::API_KEY => "sp-key" })

        StatuspageApi.any_instance.stubs(:pages).raises(StatuspageApi::Unauthenticated, "Statuspage answered 401: Could not authenticate")
        assert_equal "Statuspage did not accept this key. Check it was copied whole and has not expired.", Statuspage.credential_refusal({ Statuspage::API_KEY => "bad" })
      end

      test "a key reaching one page needs no page named, and one reaching several says which it reaches" do
        StatuspageApi.any_instance.expects(:incidents).with("pg1", StatuspageApi::INCIDENTS_UNRESOLVED, query: "").returns(Pages::Read.new(items: [], complete: true))
        assert_includes text(call(:list_incidents)), "No unresolved incidents on Acme."

        other = { "id" => "pg2", "name" => "Internal", "subdomain" => "acme-internal" }
        StatuspageApi.any_instance.stubs(:pages).returns(Pages::Read.new(items: [ PAGE, other ], complete: true))
        error = assert_raises(NativePack::Error) { Statuspage.new(@integration).call("list_components", environment_row: @row, arguments: {}) }
        assert_equal "This key reaches 2 pages: Acme (pg1), Internal (pg2). Name one with page.", error.message
      end

      test "components read in their groups, and the result links to the page at its own domain" do
        result = call(:list_components, "page" => "acme")

        assert_includes text(result), "Checkout (id c2), degraded_performance"
        assert_includes text(result), "Group Core (id g1):\n  API (id c1), operational"
        assert_includes text(result), "https://status.acme.io"
      end

      test "opening an incident names components by name, sets their status and asks whether to tell subscribers" do
        error = assert_raises(NativePack::Error) { call(:create_incident, "name" => "Checkout down", "body" => "Looking") }
        assert_equal "Say whether to tell subscribers with deliver_notifications, true or false. Ask the person which they want.", error.message

        StatuspageApi.any_instance.expects(:create_incident).with("pg1", {
          "name" => "Checkout down", "body" => "Looking", "status" => "investigating", "components" => { "c2" => "major_outage" },
          "component_ids" => [ "c2" ], "deliver_notifications" => false
        }).returns("id" => "i1", "name" => "Checkout down", "status" => "investigating", "shortlink" => "https://stspg.io/abc", "created_at" => "2026-10-14T10:00:00Z")

        result = call(:create_incident, "name" => "Checkout down", "body" => "Looking", "components" => { "checkout" => "major_outage" }, "deliver_notifications" => false)

        assert text(result).start_with?("Statuspage opened incident Checkout down (id i1) on Acme, investigating. Subscribers were not told.")
        assert_includes text(result), "https://stspg.io/abc"
        assert_raises(NativePack::Error) { call(:create_incident, "name" => "x", "body" => "y", "components" => { "Search" => "major_outage" }, "deliver_notifications" => true) }
        assert_raises(NativePack::Error) { call(:create_incident, "name" => "x", "body" => "y", "components" => { "API" => "down" }, "deliver_notifications" => true) }
      end

      test "an update posts its words at the status it has, and an incident without a shortlink links under the page" do
        StatuspageApi.any_instance.expects(:update_incident).with("pg1", "i1", {
          "body" => "Fixed", "status" => "resolved", "components" => { "c2" => "operational" }, "component_ids" => [ "c2" ], "deliver_notifications" => true
        }).returns("id" => "i1", "name" => "Checkout down", "status" => "resolved",
                   "incident_updates" => [ { "id" => "u2", "status" => "resolved", "body" => "Fixed", "created_at" => "2026-10-14T11:00:00Z" } ])

        result = call(:post_incident_update, "incident" => "i1", "body" => "Fixed", "status" => "resolved", "components" => { "c2" => "operational" },
                                             "deliver_notifications" => true)

        assert_includes text(result), "posted an update to Checkout down (id i1), now resolved. Subscribers were told."
        assert_includes text(result), "2026-10-14T11:00:00Z resolved (update u2): Fixed"
        assert_includes text(result), "https://status.acme.io/incidents/i1"
        assert_raises(NativePack::Error) { call(:post_incident_update, "incident" => "i1", "body" => "x", "status" => "fixed", "deliver_notifications" => true) }
      end

      test "maintenance is scheduled for its window and its components, ending after it starts" do
        StatuspageApi.any_instance.expects(:create_incident).with("pg1", {
          "name" => "Database upgrade", "body" => "Brief downtime", "status" => "scheduled", "scheduled_for" => "2026-10-20T22:00:00Z",
          "scheduled_until" => "2026-10-20T23:00:00Z", "component_ids" => [ "c1" ], "scheduled_auto_in_progress" => true, "scheduled_auto_completed" => true,
          "auto_transition_to_maintenance_state" => true, "auto_transition_to_operational_state" => true, "scheduled_remind_prior" => false,
          "deliver_notifications" => true
        }).returns("id" => "m1", "name" => "Database upgrade", "status" => "scheduled")

        call(:schedule_maintenance, "name" => "Database upgrade", "body" => "Brief downtime", "scheduled_for" => "2026-10-20T22:00:00Z",
                                    "scheduled_until" => "2026-10-20T23:00:00Z", "components" => [ "API" ], "auto_start" => true, "auto_complete" => true,
                                    "components_under_maintenance" => true, "deliver_notifications" => true)
        error = assert_raises(NativePack::Error) do
          call(:schedule_maintenance, "name" => "x", "body" => "y", "scheduled_for" => "2026-10-20T22:00:00Z", "scheduled_until" => "2026-10-20T21:00:00Z",
                                      "deliver_notifications" => true)
        end
        assert_equal "scheduled_until comes before scheduled_for. Give an end after the start.", error.message
      end

      test "a component's status is set by its name, and a group is moved into by name or left with none" do
        StatuspageApi.any_instance.expects(:update_component).with("pg1", "c2", { "status" => "major_outage", "group_id" => "g1" })
                     .returns("name" => "Checkout", "status" => "major_outage")
        assert_equal "Statuspage changed Checkout on Acme, now major_outage.", text(call(:update_component, "component" => "Checkout", "status" => "major_outage", "group" => "Core")).lines.first.strip

        StatuspageApi.any_instance.expects(:update_component).with("pg1", "c1", { "group_id" => "null" }).returns("name" => "API", "status" => "operational")
        call(:update_component, "component" => "c1", "group" => "none")
        assert_raises(NativePack::Error) { call(:update_component, "component" => "Core", "status" => "major_outage") }
      end

      test "a subscriber is added by email for the components named, and an SMS one needs its country" do
        StatuspageApi.any_instance.expects(:add_subscriber).with("pg1", { "email" => "ana@acme.io", "component_ids" => [ "c1" ] })
                     .returns("id" => "s1", "email" => "ana@acme.io")
        assert_includes text(call(:add_subscriber, "email" => "ana@acme.io", "components" => [ "API" ])), "Statuspage subscribed ana@acme.io (id s1) to Acme and asked them to confirm."

        error = assert_raises(NativePack::Error) { call(:add_subscriber, "phone_number" => "5551234") }
        assert_equal "An SMS subscriber needs phone_country, its two letter country.", error.message
      end

      test "a postmortem is published only once the person said whether subscribers hear of it" do
        assert_raises(NativePack::Error) { call(:publish_postmortem, "incident" => "i1") }
        StatuspageApi.any_instance.expects(:publish_postmortem).with("pg1", "i1", "notify_subscribers" => true).returns({})

        assert_includes text(call(:publish_postmortem, "incident" => "i1", "notify_subscribers" => true)), "published the postmortem of incident i1 on Acme and told its subscribers"
      end

      test "a page's settings are changed by the ones named, its website sent as Statuspage's url" do
        assert_raises(NativePack::Error) { call(:update_page) }
        StatuspageApi.any_instance.expects(:update_page).with("pg1", { "url" => "https://acme.io", "allow_sms_subscribers" => false })
                     .returns("id" => "pg1", "name" => "Acme", "domain" => "status.acme.io")

        assert_includes text(call(:update_page, "website" => "https://acme.io", "allow_sms_subscribers" => false)), "Statuspage changed url and allow sms subscribers on Acme."
      end

      test "a page's template and colours are set with its other settings, and its status embed is read and changed" do
        StatuspageApi.any_instance.expects(:update_page).with("pg1", { "branding" => "premium", "css_reds" => "#e5484d" }).returns("id" => "pg1")
        assert_includes text(call(:update_page, "branding" => "premium", "css_reds" => "#e5484d")), "Statuspage changed branding and css reds on Acme."

        StatuspageApi.any_instance.stubs(:status_embed).returns("position" => "bottom-left", "incident_background_color" => "#000000")
        assert_includes text(call(:get_status_embed)), "position: bottom-left\nincident background color: #000000"
        StatuspageApi.any_instance.expects(:update_status_embed).with("pg1", { "position" => "top-right" }).returns({})
        assert_includes text(call(:update_status_embed, "position" => "top-right")), "Statuspage changed the status embed's position on Acme."
        assert_raises(NativePack::Error) { call(:update_status_embed) }
      end

      test "subscribers are unsubscribed, reminded and taken back in bulk, by id or all, never more than Statuspage takes" do
        StatuspageApi.any_instance.expects(:unsubscribe_many).with("pg1", subscribers: %w[s1 s2], type: nil, state: "all", quietly: true).returns({})
        assert_includes text(call(:unsubscribe_subscribers, "subscribers" => %w[s1 s2], "state" => "all", "quietly" => true)),
                        "Statuspage is unsubscribing 2 subscribers from Acme, without telling them."
        StatuspageApi.any_instance.expects(:resend_confirmations).with("pg1", subscribers: :all).returns({})
        assert_includes text(call(:resend_confirmations, "subscribers" => [ "all" ])), "every subscriber"
        StatuspageApi.any_instance.expects(:reactivate).with("pg1", subscribers: %w[s1], type: "email").returns({})
        call(:reactivate_subscribers, "subscribers" => %w[s1], "type" => "email")

        assert_raises(NativePack::Error) { call(:unsubscribe_subscribers, "subscribers" => Array.new(101) { |index| "s#{index}" }) }
        assert_raises(NativePack::Error) { call(:resend_confirmations, "subscribers" => %w[all s1]) }
        assert_raises(NativePack::Error) { call(:reactivate_subscribers, "subscribers" => %w[s1], "type" => "teams") }

        StatuspageApi.any_instance.stubs(:subscriber_histogram).returns("email" => { "active" => 3, "quarantined" => 1 })
        assert_includes text(call(:subscriber_histogram)), "email: 3 active, 1 quarantined"
      end

      test "a Self metrics provider is the only kind made, and a metric takes readings at the times given" do
        StatuspageApi.any_instance.expects(:create_metrics_provider).with("pg1", "type" => "Self").returns("id" => "mp1")
        assert_includes text(call(:create_metrics_provider)), "Statuspage added a Self metrics provider (id mp1) to Acme."
        assert_not Statuspage.tool_definitions.find { |each| each.name == "create_metrics_provider" }.params_schema["properties"].key?("api_key")

        StatuspageApi.any_instance.stubs(:metrics).returns(Pages::Read.new(items: [ { "id" => "m1", "name" => "Latency", "metrics_provider_id" => "mp1" } ], complete: true))
        StatuspageApi.any_instance.expects(:add_metric_data).with("pg1", { "m1" => [ { "timestamp" => 1_791_936_000, "value" => 120.5 } ] }).returns({})
        assert_includes text(call(:add_metric_data, "metric" => "latency", "points" => [ { "at" => "2026-10-14T00:00:00Z", "value" => 120.5 } ])),
                        "Statuspage took 1 reading for Latency on Acme."
        assert_raises(NativePack::Error) { call(:add_metric_data, "metric" => "m1", "points" => [ { "at" => "2026-10-14T00:00:00Z", "value" => "fast" } ]) }

        StatuspageApi.any_instance.expects(:create_metric).with("pg1", "mp1", { "name" => "Errors", "suffix" => "%", "display" => true, "decimal_places" => 1 })
                     .returns("id" => "m2", "name" => "Errors")
        call(:create_metric, "provider" => "mp1", "name" => "Errors", "suffix" => "%", "display" => true, "decimal_places" => 1)
      end

      test "page access users and groups are named by email or name, and what they see is added to, replaced or removed" do
        StatuspageApi.any_instance.stubs(:page_access_users).returns(Pages::Read.new(items: [ { "id" => "u1", "email" => "ana@acme.io" } ], complete: true))
        StatuspageApi.any_instance.stubs(:page_access_groups).returns(Pages::Read.new(items: [ { "id" => "g9", "name" => "Partners" } ], complete: true))
        StatuspageApi.any_instance.stubs(:metrics).returns(Pages::Read.new(items: [ { "id" => "m1", "name" => "Latency" } ], complete: true))

        StatuspageApi.any_instance.expects(:create_page_access_user).with("pg1", { "email" => "bo@acme.io", "page_access_group_ids" => [ "g9" ] }).returns("id" => "u2", "email" => "bo@acme.io")
        assert_includes text(call(:create_page_access_user, "email" => "bo@acme.io", "groups" => [ "partners" ])), "Statuspage let bo@acme.io (id u2) see Acme."
        assert_raises(NativePack::Error) { call(:create_page_access_user, "groups" => [ "Partners" ]) }

        StatuspageApi.any_instance.expects(:change_page_access_user_access).with("pg1", "u1", :components, :remove, [ "c2" ]).returns({})
        assert_includes text(call(:change_page_access_user_access, "user" => "ana@acme.io", "list" => "components", "change" => "remove", "items" => [ "Checkout" ])),
                        "Statuspage removed 1 components for ana@acme.io on Acme."
        StatuspageApi.any_instance.expects(:change_page_access_user_access).with("pg1", "u1", :metrics, :add, [ "m1" ]).returns({})
        call(:change_page_access_user_access, "user" => "u1", "list" => "metrics", "change" => "add", "items" => [ "Latency" ])

        StatuspageApi.any_instance.expects(:change_page_access_group_components).with("pg1", "g9", :replace, %w[c1 c2]).returns({})
        call(:change_page_access_group_components, "group" => "Partners", "change" => "replace", "components" => %w[API Checkout])
        assert_raises(NativePack::Error) { call(:change_page_access_group_components, "group" => "Partners", "change" => "swap", "components" => [ "API" ]) }
      end

      private

      def call(tool, arguments = {}) = @pack.call(tool.to_s, environment_row: @row, arguments: arguments)

      def text(result) = result["content"].map { |part| part["text"] }.join("\n")
    end
  end
end
