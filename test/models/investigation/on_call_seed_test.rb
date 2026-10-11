require "test_helper"

class Investigation::OnCallSeedTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include OnCallTestHelper
  include PagingTestHelper

  setup { alert_run_with_restart_fix }

  test "a run an alert started is told nobody asked, the changes it may make on its own and whether it pages" do
    grant_investigator(@api)
    rule = restart_rule
    restart_rule(enabled: false, metric: "cpu")
    @workspace.update!(on_call_paging_enabled: true)

    facts = Investigation::IncidentSeed.new(@investigation).gather[Investigation::Seeding::KEY_ON_CALL]

    assert_match "Nobody asked", facts["started_from"]
    assert_equal [ { "rule" => rule.sentence, "fix_step" => { "tool" => "restart", "resource" => "web" } } ], facts["unattended_rules"]
    assert facts["pages_on_call"]
  end

  test "a run an alert started is told who each on-call tool has on call now, read as the run, and why one cannot be read" do
    connect_pagerduty!(@workspace)
    opsgenie = connect_opsgenie!(@workspace)
    Integrations::PagerdutyApi.any_instance.stubs(:on_calls).returns([
      { "escalation_level" => 1, "user" => { "name" => "Bob Ruiz", "email" => "bob@example.com" }, "schedule" => { "summary" => "Platform" },
        "escalation_policy" => { "summary" => "Checkout" } }
    ])
    Integrations::OpsgenieApi.any_instance.stubs(:schedules).raises(Integrations::OpsgenieApi::Error, "Opsgenie answered 403: restricted")
    opsgenie.tools.find_by!(name: "close_alert").update!(enabled: false)

    tools = Investigation::IncidentSeed.new(@investigation).gather.dig(Investigation::Seeding::KEY_ON_CALL, "paging_tools")

    pagerduty = tools.find { |tool| tool["tool"] == "pagerduty" }
    assert_equal [ { "name" => "Bob Ruiz", "email" => "bob@example.com", "covers" => "Platform schedule, level 1 of Checkout" } ], pagerduty["on_call_now"]
    assert_match "PagerDuty service", pagerduty["pages"]
    assert_nil pagerduty["cannot_page"]
    og = tools.find { |tool| tool["tool"] == "opsgenie" }
    assert_equal "Opsgenie did not say who is on call: Opsgenie answered 403: restricted.", og["on_call_unread"]
    assert_match "close_alert is switched off", og["cannot_page"]
    read = @workspace.ability_invocations.find_by!(action_key: "pagerduty.browse_schedules")
    assert_equal [ SystemAgent.investigator, AbilityGateway::SOURCE_INVESTIGATION ], [ read.principal, read.source ]
  end

  test "a run a person started carries no on-call facts" do
    @investigation.update_columns(trigger_source: Investigation::TRIGGER_DASHBOARD)

    assert_nil Investigation::IncidentSeed.new(@investigation.reload).gather[Investigation::Seeding::KEY_ON_CALL]
  end

  test "a step written as a capability keeps the resource it acts on" do
    assert_equal @web, @plan.steps.sole.resource
  end

  test "once a run an alert started answers, Halon follows up, and never for a person's run" do
    delivery = stub(answered!: nil)
    runner = Investigation::Runner.new(@investigation)
    runner.stubs(:delivery).returns(delivery)

    assert_enqueued_with(job: OnCallFollowUpJob, args: [ @investigation.id ]) { runner.send(:deliver, nil) }
    @investigation.update_columns(trigger_source: Investigation::TRIGGER_DASHBOARD)
    assert_no_enqueued_jobs(only: OnCallFollowUpJob) { runner.send(:deliver, nil) }
  end
end
