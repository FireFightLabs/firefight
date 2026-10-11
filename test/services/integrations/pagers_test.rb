require "test_helper"

module Integrations
  class PagersTest < ActiveSupport::TestCase
    include PagingTestHelper

    setup do
      @workspace = workspaces(:slack_workspace_one)
      @calls = []
    end

    test "PagerDuty pages the one service named, each call authorized as the tool that makes the same change" do
      pager = session(connect_pagerduty!(@workspace))
      PagerdutyApi.any_instance.stubs(:services).with(query: "checkout").returns([ { "id" => "P1", "name" => "Checkout" }, { "id" => "P2", "name" => "Checkout API" } ])
      PagerdutyApi.any_instance.expects(:create_incident).with(service_id: "P1", title: "INC-001 Down", details: "Why", incident_key: "k")
                  .returns(pagerduty_incident)

      raised = pager.page(title: "INC-001 Down", details: "Why", target: "checkout", key: "k")

      assert_equal [ "PGR0VU2", "#42", "https://acme.pagerduty.com/incidents/PGR0VU2" ], [ raised.external_id, raised.reference, raised.url ]
      assert_equal [ [ "browse_services", { "action" => "list", "query" => "checkout" } ],
                     [ "manage_incidents", { "action" => "create", "service" => "P1", "title" => "INC-001 Down", "incident_key" => "k" } ] ], @calls
    end

    test "PagerDuty says which services a name could be, and that a switched off tool is why it cannot page" do
      integration = connect_pagerduty!(@workspace)
      PagerdutyApi.any_instance.stubs(:services).returns([ { "id" => "P1", "name" => "Checkout API" }, { "id" => "P2", "name" => "Checkout web" } ])
      error = assert_raises(Paging::Failed) { session(integration).page(title: "t", details: "d", target: "Checkout", key: "k") }
      assert_equal "Several PagerDuty services match Checkout: Checkout API and Checkout web. Name one.", error.message

      integration.tools.find_by!(name: "manage_incidents").update!(enabled: false)
      PagerdutyApi.any_instance.stubs(:service).returns("id" => "P1")
      error = assert_raises(Paging::Failed) { session(integration.reload).page(title: "t", details: "d", target: "P1ABCDE", key: "k") }
      assert_equal "PagerDuty's manage_incidents is switched off, so Firefight cannot raise a PagerDuty incident.", error.message
    end

    test "PagerDuty reads who is on call with their emails, first level first, and resolves an incident by its id" do
      pager = session(connect_pagerduty!(@workspace))
      PagerdutyApi.any_instance.stubs(:on_calls).returns([
        { "escalation_level" => 2, "user" => { "summary" => "Cara", "email" => "cara@example.com" }, "escalation_policy" => { "summary" => "Checkout" } },
        { "escalation_level" => 1, "user" => { "summary" => "Bob", "name" => "Bob Ruiz", "email" => "bob@example.com" },
          "schedule" => { "summary" => "Platform" }, "escalation_policy" => { "summary" => "Checkout" } }
      ])
      PagerdutyApi.any_instance.expects(:update_status).with("PGR0VU2", status: "resolved").returns({})

      on_call = pager.on_call
      pager.resolve("PGR0VU2")

      assert_equal [ Paging::OnCall.new(name: "Bob Ruiz", email: "bob@example.com", covers: "Platform schedule, level 1 of Checkout"),
                     Paging::OnCall.new(name: "Cara", email: "cara@example.com", covers: "level 2 of Checkout") ], on_call
      assert_equal "browse_schedules", @calls.first.first
    end

    test "Opsgenie raises an alert for the team named, waits for its id, and acts on one by its alias until it has one" do
      pager = session(connect_opsgenie!(@workspace))
      pager.send(:api).stubs(:sleep)
      OpsgenieApi.any_instance.expects(:create_alert).with(message: "INC-001 Down", description: "Why", alias_name: "k",
                                                           responders: [ { "type" => "escalation", "name" => "Checkout" } ]).returns("requestId" => "r1")
      OpsgenieApi.any_instance.stubs(:request_status).with("r1").returns("isSuccess" => true, "alertId" => "a1")
      OpsgenieApi.any_instance.expects(:close).with("k", "alias", note: nil).returns("requestId" => "r2")
      OpsgenieApi.any_instance.stubs(:request_status).with("r2").returns("isSuccess" => true, "status" => "Closed")

      assert_equal "a1", pager.page(title: "INC-001 Down", details: "Why", target: "escalation: Checkout", key: "k").external_id
      pager.resolve(nil, key: "k")

      assert_equal %w[create_alert close_alert], @calls.map(&:first)
    end

    test "Opsgenie pages a team by a bare name, refuses a kind it does not page, and says when it could not close" do
      pager = session(connect_opsgenie!(@workspace))
      assert_equal({ "type" => "team", "name" => "Platform" }, pager.send(:responder_for, "Platform"))
      assert_equal({ "type" => "user", "username" => "bob@example.com" }, pager.send(:responder_for, "user: bob@example.com"))
      assert_match "not a service", assert_raises(Paging::Failed) { pager.send(:responder_for, "service: Checkout") }.message

      OpsgenieApi.any_instance.stubs(:acknowledge).returns("requestId" => "r3")
      OpsgenieApi.any_instance.stubs(:request_status).returns("isSuccess" => false, "status" => "Alert does not exist")
      assert_equal "Opsgenie could not acknowledge alert a1: Alert does not exist.", assert_raises(Paging::Failed) { pager.acknowledge("a1") }.message
    end

    test "only on-call tools page, each says what a page goes to, and an alert source of its kind reports on its pages" do
      assert Paging.pages?(Providers::Pagerduty.key)
      assert Paging.pages?(Providers::Opsgenie.key)
      assert_not Paging.pages?("linear")
      assert Paging.reported_by?(AlertSource::PROVIDER_OPSGENIE)
      assert_not Paging.reported_by?(AlertSource::PROVIDER_GENERIC)
      assert_match "PagerDuty service", Paging.target_words(Providers::Pagerduty.key)
      assert_equal "123", Paging.page_id_of(Paging.key_for("123"))
      assert_nil Paging.page_id_of("someone-elses-key")
    end

    private

    def session(integration)
      Paging.session(integration) do |tool, arguments, &run|
        @calls << [ tool.name, arguments ]
        run.call
      end
    end
  end
end
