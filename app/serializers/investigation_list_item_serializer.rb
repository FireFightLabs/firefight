# One run in the Investigations list.
class InvestigationListItemSerializer < BaseSerializer
  object_as :investigation

  attributes(
    id: { type: :string },
    status: { type: :string },
    turns_used: { type: :number }
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

  # The answer, or why there is none, so the list reads without opening a run.
  type :string, optional: true
  def answer
    investigation.finding&.summary || investigation.stopped_because
  end

  type :string, optional: true
  def outcome
    investigation.finding&.outcome
  end

  type :string, optional: true
  def asked_by
    investigation.triggered_by.try(:actor_display_name)
  end

  type :string
  def created_at
    investigation.created_at.utc.iso8601
  end

  type :number, optional: true
  def duration_seconds
    investigation.duration_seconds
  end

  type :number
  def spent_cents
    investigation.spent_cents
  end
end
