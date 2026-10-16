# The window starts when the incident ends rather than when it closes, because a postmortem
# is usually written the next morning from the transcript. No retention set keeps everything.
class TranscriptRetentionJob < ApplicationJob
  queue_as :background

  BATCH = 500

  def perform
    Workspace.where.not(transcript_retention_days: nil).find_each do |workspace|
      purge(workspace)
    end
  end

  private

  def purge(workspace)
    incidents = workspace.incidents.ended_before(Time.current - workspace.transcripts_purge_after).select(:id)

    purged = workspace.incident_transcript_messages
      .where(incident_id: incidents)
      .in_batches(of: BATCH)
      .delete_all
    files = purge_files(workspace, incidents)

    return if purged.zero? && files.zero?

    Rails.logger.info({ event: "transcript_retention.purged", workspace_id: workspace.id, messages: purged, files: files })
  end

  # Files shared with Halon in an incident's channel are part of what was said there, so they go with the transcript.
  # Destroyed one by one, since each lets go of its bytes in the object store.
  def purge_files(workspace, incidents)
    Chat::Attachment.of_incidents(workspace, incidents).find_each(batch_size: BATCH).count(&:destroy)
  end
end
