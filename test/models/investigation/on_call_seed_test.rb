require "test_helper"

class Investigation::OnCallSeedTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include OnCallTestHelper

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
