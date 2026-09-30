# What an ended incident came to, in one line, for whoever looks at what it touched later. It is read from what people
# and the incident's own record already say, never written by a model here: a completed postmortem's summary first,
# then the incident's summary. The running summary, a digest of the channel, is used only where the workspace lets
# people read transcripts and the incident is not private, since it would otherwise show what the channel said.
module Incident::Outcome
  extend ActiveSupport::Concern

  # How far back past incidents are shown, and how many.
  PAST_WINDOW_DAYS = 180
  PAST_SHOWN = 5
  OUTCOME_LENGTH = 200

  # Where the line came from, as a person reads it.
  SOURCE_POSTMORTEM = "From the postmortem".freeze
  SOURCE_SUMMARY = "From the incident summary".freeze
  SOURCE_RUNNING_SUMMARY = "From the running summary".freeze

  Line = Data.define(:text, :source)

  class_methods do
    # Ended incidents that named any of these catalog entries, each with what it named. Deleted ones are gone for everyone.
    def past_on(workspace, entry_ids)
      IncidentFieldValue.joins(:incident).merge(closed.ended_since(PAST_WINDOW_DAYS.days.ago))
                        .where(catalog_entry_id: entry_ids, incidents: { workspace_id: workspace.id, deleted_at: nil })
                        .includes(incident: %i[postmortem incident_summary workspace])
    end
  end

  # nil when nothing was written about how it ended.
  def outcome
    return @outcome if defined?(@outcome)

    completed = postmortem if postmortem&.status == Postmortem::STATUS_COMPLETED
    running = incident_summary&.content if !is_private && workspace.transcript_access_blocked_reason.nil?
    found = [ [ completed&.summary, SOURCE_POSTMORTEM ], [ summary, SOURCE_SUMMARY ], [ running, SOURCE_RUNNING_SUMMARY ] ]
            .find { |text, _| text.present? }
    @outcome = found && Line.new(text: first_sentence(found.first), source: found.last)
  end

  def ended_at = resolved_at || updated_at

  private

  def first_sentence(text)
    plain = ActionView::Base.full_sanitizer.sanitize(text.to_s).squish
    (plain[/\A.+?[.!?](?=\s|\z)/] || plain).truncate(OUTCOME_LENGTH, separator: " ")
  end
end
