module Incident::Serialization
  extend ActiveSupport::Concern

  def to_context_hash
    {
      identifier:, name:, summary:,
      severity: incident_severity.name,
      status: incident_status.name,
      declared_at: declared_at&.iso8601,
      detected_at: detected_at&.iso8601,
      resolved_at: resolved_at&.iso8601,
      duration_minutes: time_to_resolve,
      declared_by: declared_by.user.name,
      lead: lead&.user&.name,
      custom_fields:
    }
  end

  def to_full_context(workspace: self.workspace)
    {
      **to_context_hash,
      timeline_events: incident_events.chronological.includes(:actor).map(&:to_context_hash),
      transcript: IncidentTranscriptCache.grouped_messages(self, workspace: workspace),
      actions: incident_actions.active.map(&:to_context_hash),
      shoutouts: shoutouts.map(&:to_context_hash)
    }
  end
end
