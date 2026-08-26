require "test_helper"

# The transcript is scaffolding. What was worked out in it survives as timeline
# milestones and, where one exists, as the postmortem, so purging drops the
# messages and not the memory.
class TranscriptRetentionJobTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @workspace.update!(transcript_retention_days: 30)
  end

  test "leaves an incident that is still open alone, however old the messages" do
    message = transcript_message(posted_at: 1.year.ago)

    TranscriptRetentionJob.perform_now

    assert IncidentTranscriptMessage.exists?(message.id)
  end

  test "leaves a recently closed incident alone" do
    close!(resolved_at: 2.days.ago)
    message = transcript_message

    TranscriptRetentionJob.perform_now

    assert IncidentTranscriptMessage.exists?(message.id)
  end

  test "purges an incident closed longer ago than the window" do
    message = transcript_message
    close!(resolved_at: 90.days.ago)

    TranscriptRetentionJob.perform_now

    assert_not IncidentTranscriptMessage.exists?(message.id)
  end

  # The whole point of purging the raw messages rather than the incident. What
  # was worked out in the conversation lives on the timeline with the quote.
  test "the milestones survive the purge, with their quotes" do
    message = transcript_message
    note = @incident.incident_events.create!(
      event_type: IncidentEvent::MILESTONE_NOTED,
      metadata: { kind: "root_cause", statement: "The pooler ran out", message_text: "found it" }
    )
    close!(resolved_at: 90.days.ago)

    TranscriptRetentionJob.perform_now

    assert_not IncidentTranscriptMessage.exists?(message.id)
    assert IncidentEvent.exists?(note.id)
    assert_equal "found it", note.reload.metadata["message_text"]
  end

  test "a workspace that keeps everything keeps everything" do
    @workspace.update!(transcript_retention_days: nil)
    message = transcript_message
    close!(resolved_at: 5.years.ago)

    TranscriptRetentionJob.perform_now

    assert IncidentTranscriptMessage.exists?(message.id)
  end

  test "another workspace's window does not reach these messages" do
    workspaces(:slack_workspace_two).update!(transcript_retention_days: 1)
    message = transcript_message
    close!(resolved_at: 90.days.ago)
    @workspace.update!(transcript_retention_days: nil)

    TranscriptRetentionJob.perform_now

    assert IncidentTranscriptMessage.exists?(message.id)
  end

  private

  def transcript_message(posted_at: 1.hour.ago)
    IncidentTranscriptMessage.create!(
      workspace: @workspace, incident: @incident, message_id: "17#{rand(10**8)}.0001",
      platform_user_id: @member.platform_user_id, workspace_membership: @member,
      content: "found it, the pooler ran out", posted_at: posted_at
    )
  end

  def close!(resolved_at:)
    @incident.update_columns(
      incident_status_id: @workspace.incident_statuses.closed.active.first.id,
      resolved_at: resolved_at,
      updated_at: resolved_at
    )
  end
end
