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

    return if purged.zero?

    Rails.logger.info({ event: "transcript_retention.purged", workspace_id: workspace.id, messages: purged })
  end
end
