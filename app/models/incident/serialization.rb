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
      declared_by: declared_by&.actor_display_name,
      lead: lead&.user&.name,
      custom_fields: custom_fields_for_display
    }
  end

  def to_full_context(workspace: self.workspace)
    {
      **to_context_hash,
      timeline_events: incident_events.undismissed.chronological.includes(:actor).map(&:to_context_hash),
      actions: incident_actions.active.map(&:to_context_hash),
      shoutouts: shoutouts.map(&:to_context_hash),
      runbooks: runbooks_context
    }
  end

  private

  def runbooks_context
    incident_runbooks.includes(runbook: :runbook_steps).order(:created_at).filter_map do |incident_runbook|
      runbook = incident_runbook.runbook
      next unless runbook.deleted_at.nil?

      {
        name: runbook.name,
        summary: runbook.summary,
        external_url: runbook.external_url,
        steps: runbook.runbook_steps.map { |step| { title: step.title, instruction: step.instruction } }
      }
    end
  end
end
