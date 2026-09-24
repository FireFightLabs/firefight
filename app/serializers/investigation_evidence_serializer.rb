# One claim of a finding and the steps behind it.
class InvestigationEvidenceSerializer < BaseSerializer
  object_as :evidence

  attributes(id: { type: :string }, claim: { type: :string })

  type "number[]"
  def steps
    evidence.citations.filter_map { |citation| citation.source.try(:position) }
  end
end
