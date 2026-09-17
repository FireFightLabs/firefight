# What an incident looks like to someone asking whether this has happened before. The parts people
# wrote, not the machinery: what it is, what fired, and what was said while working it.
module Incident::Searchable
  extend ActiveSupport::Concern
  include SearchEmbedding::Writing

  SUMMARY_LIMIT = 10
  NOTE_LIMIT = 20

  def search_text
    [
      "#{identifier} #{name}",
      summary,
      incident_severity&.name,
      incident_type&.name,
      alerts.map(&:title).uniq.join(". "),
      past_summaries.join("\n"),
      milestone_notes.join("\n")
    ].compact_blank.join("\n")
  end

  def search_facts
    {
      id: id, identifier: identifier, name: name, summary: summary,
      status: incident_status.name, open: !incident_status.incident_lifecycle_stage.closed?,
      severity: incident_severity.name, declared_at: declared_at&.utc&.iso8601
    }.compact
  end

  private

  # The summary is rewritten as people learn what is going on, so the old ones are the story.
  def past_summaries
    incident_updates.where.not(summary: [ nil, "" ]).order(created_at: :desc)
      .limit(SUMMARY_LIMIT).pluck(:summary).uniq - [ summary ]
  end

  def milestone_notes
    incident_events.where(event_type: IncidentEvent::MILESTONE_NOTED).order(created_at: :desc)
      .limit(NOTE_LIMIT).filter_map { |event| event.metadata["statement"] }
  end
end
