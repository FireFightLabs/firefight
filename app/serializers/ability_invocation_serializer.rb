class AbilityInvocationSerializer < BaseSerializer
  object_as :invocation

  DECISION_UNION = Ability::Invocation::DECISIONS.map(&:inspect).join(" | ")
  OUTCOME_UNION = Ability::Invocation::OUTCOMES.map(&:inspect).join(" | ")

  type :string
  def id
    invocation.id
  end

  # Who asked or acted as a person reads it, such as "Halon", never the machine label the row keeps.
  type :string
  def principal_name
    invocation.principal_name
  end

  attributes(
    action_key: { type: :string }
  )

  type :string, optional: true
  def triggered_by_label
    invocation.triggered_by_label
  end

  type :string, optional: true
  def risk_level
    invocation.risk_level
  end

  type DECISION_UNION
  def decision
    invocation.decision
  end

  type OUTCOME_UNION, optional: true
  def outcome
    invocation.outcome
  end

  type :string, optional: true
  def error_summary
    invocation.error_summary
  end

  type :number, optional: true
  def duration_ms
    invocation.duration_ms
  end

  type "Record<string, string[]>"
  def scope
    invocation.scope
  end

  type :string, optional: true
  def approval_id
    invocation.approval_id
  end

  # The connection a tool's action runs through, as a person tells it apart, such as "Production (Acme Cloud)".
  type :string, optional: true
  def connection
    invocation.connection_name
  end

  type :string, optional: true
  def source
    invocation.source
  end

  type :string, optional: true
  def source_label
    Ability::Source.label(invocation.source)
  end

  # Why a change Halon made in a chat ran without the person's yes, such as "Made without asking because it is a safe
  # change.", or null.
  type :string, optional: true
  def unasked_because
    invocation.unasked_because
  end

  type :string
  def created_at
    invocation.created_at.iso8601
  end

  type :string, optional: true
  def completed_at
    invocation.completed_at&.iso8601
  end
end
