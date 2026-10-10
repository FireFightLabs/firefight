require "test_helper"

class Investigation::AlertStartTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @workspace.update!(alert_investigations_enabled: true, alert_storm_ceiling_cents: 1_000)
    @incident = incidents(:active_critical_ws1)
    @incident.update_columns(source: Incident::SOURCE_ALERT)
    Investigation.stubs(:start_refusal).returns(nil)
    @adapter = stub
    WorkspaceAdapter.stubs(:for).returns(@adapter)
  end

  test "an alert's incident starts Halon once, as the alert, on what is left of the hour's ceiling up to its usual budget" do
    @workspace.investigations.create!(subject: incidents(:resolved_minor_ws1), trigger_source: Investigation::TRIGGER_ALERT, max_turns: 10,
                                      max_spend_cents: 400, status: Investigation::STATUS_SUCCEEDED, spent_micros: 7_500_000)

    assert_enqueued_jobs(1, only: InvestigationJob) { assert_equal Investigation::AlertStart::OUTCOME_STARTED, Investigation::AlertStart.start!(@incident) }

    run = @incident.investigations.live.sole
    assert_equal [ Investigation::TRIGGER_ALERT, 250 ], [ run.trigger_source, run.max_spend_cents ]
    assert_equal Investigation::AlertStart::OUTCOME_RUNNING, Investigation::AlertStart.start!(@incident)
    assert_equal 1, @incident.investigations.count
  end

  test "once too little of the hour's ceiling is left, the incident says Halon did not start and offers to start it" do
    @workspace.investigations.create!(subject: incidents(:resolved_minor_ws1), trigger_source: Investigation::TRIGGER_ALERT, max_turns: 10, max_spend_cents: 980)
    @adapter.expects(:post_alert_run_held).with do |channel_id:, incident:, reason:, rerun:|
      channel_id == @incident.channel_id && incident == @incident && rerun && reason.include?("have used the $10 they may spend in an hour")
    end.returns(message_id: "1.2", channel_id: @incident.channel_id)

    assert_no_enqueued_jobs(only: InvestigationJob) { assert_equal Investigation::AlertStart::OUTCOME_HELD, Investigation::AlertStart.start!(@incident) }
  end

  test "a run older than an hour no longer counts, and a person's run never does" do
    @workspace.investigations.create!(subject: incidents(:resolved_minor_ws1), trigger_source: Investigation::TRIGGER_ALERT, max_turns: 10,
                                      max_spend_cents: 980, created_at: 2.hours.ago)
    @workspace.investigations.create!(subject: incidents(:resolved_minor_ws1), trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10,
                                      max_spend_cents: 400, status: Investigation::STATUS_SUCCEEDED, spent_micros: 9_900_000)

    assert_equal 0, @workspace.storm_committed_cents
    assert_equal Investigation::AlertStart::OUTCOME_STARTED, Investigation::AlertStart.start!(@incident)
  end

  test "nothing starts while the switch is off or for an incident a person declared" do
    @workspace.update!(alert_investigations_enabled: false)
    assert_equal Investigation::AlertStart::OUTCOME_OFF, Investigation::AlertStart.start!(@incident)

    @workspace.update!(alert_investigations_enabled: true)
    @incident.update_columns(source: Incident::SOURCE_SLACK)
    assert_equal Investigation::AlertStart::OUTCOME_OFF, Investigation::AlertStart.start!(@incident.reload)
    assert_empty @incident.investigations
  end

  test "a workspace Halon cannot run in is told why, with no button that would only be refused" do
    Investigation.stubs(:start_refusal).returns("AI features are not available.")
    @adapter.expects(:post_alert_run_held).with { |reason:, rerun:, **| reason == "Halon did not start on this alert. AI features are not available." && !rerun }
                                          .returns(message_id: "1.2", channel_id: "C1")

    assert_equal Investigation::AlertStart::OUTCOME_HELD, Investigation::AlertStart.start!(@incident)
  end

  test "the incident's workflow starts it once the channel is there, and a retried step never starts it twice" do
    workflow = IncidentCreationWorkflow.new
    step = stub(checkpoint: nil)
    step.expects(:update_column).with(:checkpoint, { "result" => Investigation::AlertStart::OUTCOME_STARTED })

    assert_equal({ "outcome" => Investigation::AlertStart::OUTCOME_STARTED },
                 workflow.start_alert_investigation(workflow: stub(subject: @incident), step: step, input: {}))
    done = stub(checkpoint: { "result" => Investigation::AlertStart::OUTCOME_STARTED })
    Investigation::AlertStart.expects(:start!).never
    workflow.start_alert_investigation(workflow: stub(subject: @incident), step: done, input: {})
  end
end
