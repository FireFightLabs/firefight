# One run in full, with what it was asked, what it found and every step behind it, each with the ledger's receipt.
class InvestigationDetailSerializer < BaseSerializer
  object_as :investigation

  attributes(
    id: { type: :string },
    status: { type: :string }
  )

  type :string
  def trigger
    investigation.trigger_source
  end

  type :string, optional: true
  def incident_id
    investigation.incident&.id
  end

  type :string, optional: true
  def incident_identifier
    investigation.incident&.identifier
  end

  type :string, optional: true
  def incident_name
    investigation.incident&.name
  end

  # What whoever asked said was wrong, the run's own question.
  type :string, optional: true
  def question
    investigation.brief&.dig(Investigation::Brief::KEY_SYMPTOM)
  end

  has_one :asker, serializer: ActorCompactSerializer, optional: true do
    investigation.triggered_by
  end

  type :string
  def created_at
    investigation.created_at.utc.iso8601
  end

  type :string, optional: true
  def started_at
    investigation.started_at&.utc&.iso8601
  end

  type :string, optional: true
  def completed_at
    investigation.completed_at&.utc&.iso8601
  end

  type :number, optional: true
  def duration_seconds
    investigation.duration_seconds
  end

  type :string, optional: true
  def stopped_because
    investigation.stopped_because
  end

  has_one :finding, serializer: InvestigationFindingSerializer, optional: true

  has_many :hypotheses, serializer: InvestigationHypothesisSerializer do
    investigation.hypotheses.includes(citations: :source)
  end

  has_many :steps, serializer: InvestigationStepSerializer do
    investigation.steps.where.not(position: nil).includes(:invocation)
  end
end
