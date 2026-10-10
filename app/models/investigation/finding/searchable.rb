# A finding is the answer to an incident, so it carries the words someone would search for later.
module Investigation::Finding::Searchable
  extend ActiveSupport::Concern
  include SearchEmbedding::Writing

  def search_text
    [ summary, winning_hypothesis&.assertion, evidence_items.map(&:claim).join("\n"), gaps ].compact_blank.join("\n")
  end

  def workspace = investigation.workspace

  # A rehearsal's answer is a measurement, never something to find again as a past answer.
  # A scheduled check's answer says what it looked at, which reads like no incident and would only crowd the search.
  def search_embeddable? = !investigation.rehearsal? && !investigation.scheduled?

  def search_facts
    {
      id: id, incident: investigation.incident&.identifier, question: investigation.question, summary: summary,
      cause: winning_hypothesis&.assertion, gaps: gaps, outcome: outcome
    }.compact
  end
end
