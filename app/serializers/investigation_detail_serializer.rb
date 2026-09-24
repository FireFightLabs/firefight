# One run in full, with what it was told, what it found and every step behind it, each with the ledger's receipt.
class InvestigationDetailSerializer < InvestigationListItemSerializer
  object_as :investigation

  attributes(max_spend_cents: { type: :number })

  type :string, optional: true
  def stopped_because
    investigation.stopped_because
  end

  # What whoever asked said about it, which the run started from.
  type :string, optional: true
  def brief
    investigation.brief&.dig(Investigation::Brief::KEY_SYMPTOM)
  end

  has_one :finding, serializer: InvestigationFindingSerializer, optional: true

  has_many :hypotheses, serializer: InvestigationHypothesisSerializer do
    investigation.hypotheses.includes(citations: :source)
  end

  has_many :steps, serializer: InvestigationStepSerializer do
    investigation.steps.where.not(position: nil).includes(:invocation)
  end
end
