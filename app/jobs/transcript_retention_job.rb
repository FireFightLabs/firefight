# The transcript is scaffolding. What was worked out in it survives as timeline
# milestones and, where one was written, as the postmortem, so purging loses
# the messages and not the memory. The window starts when the incident ends
# rather than when it closes, because a postmortem is usually written the next
# morning and generating one reads the transcript.
#
# A workspace with no retention set keeps everything, which is a choice it can
# make knowing what it means.
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
