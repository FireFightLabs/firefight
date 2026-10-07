require "test_helper"

# What was worked out in the transcript survives as timeline milestones and the postmortem,
# so purging drops the messages and not the memory.
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

  test "files shared with Halon in the incident's channel go with the transcript, and its other chats keep theirs" do
    in_channel = Conversation::Opener.call(workspace: @workspace, incident: @incident, channel_id: @incident.channel_id,
                                           thread_id: "1700000000.000100", platform_user_id: @member.platform_user_id)
    shared = Chat::Attachment.take!(workspace: @workspace, uploaded_by: @member, filename: "app.log", bytes: "boom")
    in_channel.ask!("what broke?", files: [ shared ])
    personal = Conversation.start_personal!(workspace: @workspace, member: @member)
    kept = Chat::Attachment.take!(workspace: @workspace, uploaded_by: @member, filename: "mine.log", bytes: "ok")
    personal.ask!("look", files: [ kept ])
    close!(resolved_at: 90.days.ago)

    TranscriptRetentionJob.perform_now

    assert_not Chat::Attachment.exists?(shared.id)
    assert Chat::Attachment.exists?(kept.id)
    assert in_channel.chat.messages.exists?, "the conversation itself stays"
  end

  test "a file shared with an investigation of the incident goes with the transcript too" do
    shared = Chat::Attachment.take!(workspace: @workspace, uploaded_by: @member, filename: "app.log", bytes: "boom")
    InvestigationService.new(@workspace).start(@incident, trigger_source: Investigation::TRIGGER_COMMAND, triggered_by: @member, files: [ shared ])
    close!(resolved_at: 90.days.ago)

    TranscriptRetentionJob.perform_now

    assert_not Chat::Attachment.exists?(shared.id)
  end

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
