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

  type :string
  def created_at
    hypothesis.created_at.utc.iso8601
  end

  type :boolean
  def settled
    hypothesis.status != Investigation::Hypothesis::STATUS_OPEN
  end

  # A theory is settled by the last step it rests on, which is where the story tells it.
  type :number, optional: true
  def settled_after_step
    steps.max if settled
  end
end
