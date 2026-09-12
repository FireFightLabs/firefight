require "test_helper"

class InvestigationServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @member = workspace_memberships(:alice_workspace_one)
    @service = InvestigationService.new(@workspace)
    stub_post_message
  end

  test "a run records the workspace's limits as they were at the start" do
    investigation = @service.start(
      @incident, trigger_source: Investigation::TRIGGER_COMMAND, triggered_by: @member
    )

    assert_equal Workspace::INVESTIGATION_DEFAULT_MAX_TURNS, investigation.max_turns
    assert_equal Workspace::INVESTIGATION_DEFAULT_MAX_SPEND_CENTS, investigation.max_spend_cents
    assert_equal @member, investigation.triggered_by
    assert_equal Investigation::TRIGGER_COMMAND, investigation.trigger_source
  end

  test "an operator's override wins over the default" do
    @workspace.update!(investigation_max_turns: 4, investigation_max_spend_cents: 150)

    investigation = @service.start(@incident, trigger_source: Investigation::TRIGGER_COMMAND)

    assert_equal 4, investigation.max_turns
    assert_equal 150, investigation.max_spend_cents
  end

  test "the channel is told the run has started" do
    Slack::WorkspaceAdapter.any_instance.expects(:post_message).with(
      channel_id: @incident.channel_id,
      text: "Investigating #{@incident.identifier}. I will post what I find.",
      blocks: nil
    ).once

    @service.start(@incident, trigger_source: Investigation::TRIGGER_BUTTON)
  end

  test "the loop runs in the background" do
    assert_enqueued_with(job: InvestigationJob) do
      @service.start(@incident, trigger_source: Investigation::TRIGGER_COMMAND)
    end
  end

  test "a second start while one is live is refused rather than duplicated" do
    first = @service.start(@incident, trigger_source: Investigation::TRIGGER_COMMAND)

    assert_no_enqueued_jobs(only: InvestigationJob) do
      assert_nil @service.start(@incident, trigger_source: Investigation::TRIGGER_BUTTON)
    end

    assert_equal [ first ], @incident.investigations.live.to_a
  end

  test "an undelivered announcement does not lose the run" do
    Slack::WorkspaceAdapter.any_instance.stubs(:post_message).raises(AdapterError.new("channel_not_found"))

    investigation = @service.start(@incident, trigger_source: Investigation::TRIGGER_COMMAND)

    assert investigation.live?
  end
end
