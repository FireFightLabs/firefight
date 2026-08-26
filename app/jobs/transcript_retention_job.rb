# Drops the raw conversation once the incident it belonged to is long over.
#
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

  # A resolved incident stamps resolved_at. A canceled one stamps nothing, so
  # its last write is the cancel itself and updated_at is the closest thing to
  # an end. Whichever is later wins, so an incident that was reopened and
  # closed again starts its window from the second time.
  def purge(workspace)
    cutoff = Time.current - workspace.transcripts_purge_after
    incidents = workspace.incidents.terminal
      .where("GREATEST(COALESCE(incidents.resolved_at, incidents.updated_at), incidents.updated_at) <= ?", cutoff)
      .select(:id)

    purged = workspace.incident_transcript_messages
      .where(incident_id: incidents)
      .in_batches(of: BATCH)
      .delete_all

    return if purged.to_i.zero?

    Rails.logger.info({ event: "transcript_retention.purged", workspace_id: workspace.id, messages: purged })
  end
end
