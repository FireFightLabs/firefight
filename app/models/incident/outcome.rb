# What an ended incident came to, in one line, for whoever looks at what it touched later. It is read from what people
# and the incident's own record already say, never written by a model here: a completed postmortem's summary first,
# then the incident's summary, then the running summary kept during the incident.
module Incident::Outcome
  extend ActiveSupport::Concern

  # How far back past incidents are shown, and how many.
  PAST_WINDOW = 180.days
  PAST_SHOWN = 5
  OUTCOME_LENGTH = 200

  SOURCE_POSTMORTEM = "postmortem".freeze
  SOURCE_SUMMARY = "incident summary".freeze
  SOURCE_RUNNING_SUMMARY = "running summary".freeze

  Line = Data.define(:text, :source)

  class_methods do
    # Ended incidents that named any of these catalog entries, newest first, each with what it named.
    def past_on(workspace, entry_ids)
      IncidentFieldValue.joins(:incident).merge(closed)
                        .where(catalog_entry_id: entry_ids, incidents: { workspace_id: workspace.id })
                        .where("COALESCE(incidents.resolved_at, incidents.updated_at) >= ?", PAST_WINDOW.ago)
                        .includes(incident: %i[postmortem incident_summary])
    end
  end

  # nil when nothing was written about how it ended.
  def outcome
    completed = postmortem if postmortem&.status == Postmortem::STATUS_COMPLETED
    found = [
      [ completed&.summary, SOURCE_POSTMORTEM ], [ summary, SOURCE_SUMMARY ], [ incident_summary&.content, SOURCE_RUNNING_SUMMARY ]
    ].find { |text, _| text.present? }
    found && Line.new(text: first_sentence(found.first), source: found.last)
  end

  def ended_at = resolved_at || updated_at

  private

  def first_sentence(text)
    plain = ActionView::Base.full_sanitizer.sanitize(text.to_s).squish
    (plain[/\A.+?[.!?](?=\s|\z)/] || plain).truncate(OUTCOME_LENGTH, separator: " ")
  end
end
