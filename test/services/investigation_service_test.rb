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
    assert_equal Workspace::INVESTIGATION_DEFAULT_MAX_TOKENS, investigation.max_tokens
    assert_in_delta Workspace::INVESTIGATION_DEFAULT_CONFIDENCE_THRESHOLD,
                    investigation.confidence_threshold, 0.001
    assert_equal @member, investigation.triggered_by
    assert_equal Investigation::TRIGGER_COMMAND, investigation.trigger_source
  end

  test "an operator's override wins over the default" do
    @workspace.update!(investigation_max_turns: 4, investigation_confidence_threshold: 0.9)

    investigation = @service.start(@incident, trigger_source: Investigation::TRIGGER_COMMAND)

    assert_equal 4, investigation.max_turns
    assert_in_delta 0.9, investigation.confidence_threshold, 0.001
  end

  test "the channel is told the run has started" do
    Slack::WorkspaceAdapter.any_instance.expects(:post_message).with(
      channel_id: @incident.channel_id,
      text: "Investigating #{@incident.identifier}, I will post what I find.",
      blocks: nil
    ).once

    @service.start(@incident, trigger_source: Investigation::TRIGGER_BUTTON)
  end

  test "the loop runs in the background" do
    assert_enqueued_with(job: InvestigationJob) do
      @service.start(@incident, trigger_source: Investigation::TRIGGER_COMMAND)
    end
  end

  test "a second start while one is live does nothing" do
    first = @service.start(@incident, trigger_source: Investigation::TRIGGER_COMMAND)

    assert_no_enqueued_jobs(only: InvestigationJob) do
      assert_nil @service.start(@incident, trigger_source: Investigation::TRIGGER_BUTTON)
    end

    assert_equal [ first ], @incident.investigations.live.to_a
  end

  test "the live run is what a second asker attaches to" do
    assert_nil @service.live_for(@incident)

    investigation = @service.start(@incident, trigger_source: Investigation::TRIGGER_COMMAND)
    assert_equal investigation, @service.live_for(@incident)

    investigation.finish!(status: Investigation::STATUS_SUCCEEDED)
    assert_nil @service.live_for(@incident)
  end

  test "an undelivered announcement does not lose the run" do
    Slack::WorkspaceAdapter.any_instance.stubs(:post_message).raises(AdapterError.new("channel_not_found"))

    investigation = @service.start(@incident, trigger_source: Investigation::TRIGGER_COMMAND)

    assert investigation.live?
  end
end
