# A finding is the answer to an incident, so it carries the words someone would search for later.
module Investigation::Finding::Searchable
  extend ActiveSupport::Concern
  include SearchEmbedding::Writing

  def search_text
    [ summary, winning_hypothesis&.assertion, evidence_items.map(&:claim).join("\n"), gaps ].compact_blank.join("\n")
  end

  def workspace = investigation.workspace

  def search_facts
    {
      id: id, incident: investigation.incident&.identifier, summary: summary,
      cause: winning_hypothesis&.assertion, gaps: gaps, outcome: outcome
    }.compact
  end
end
