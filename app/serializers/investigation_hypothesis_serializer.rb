# One theory of a run, and the steps that settled it.
class InvestigationHypothesisSerializer < BaseSerializer
  object_as :hypothesis

  attributes(id: { type: :string }, assertion: { type: :string }, status: { type: :string })

  type :number, optional: true
  def confidence
    hypothesis.confidence&.to_f
  end

  type "number[]"
  def steps
    hypothesis.citations.filter_map { |citation| citation.source.try(:position) }
  end
end
