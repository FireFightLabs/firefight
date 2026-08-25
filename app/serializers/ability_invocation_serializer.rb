class AbilityInvocationSerializer < BaseSerializer
  object_as :invocation

  DECISION_UNION = Ability::Invocation::DECISIONS.map(&:inspect).join(" | ")
  OUTCOME_UNION = Ability::Invocation::OUTCOMES.map(&:inspect).join(" | ")

  type :string
  def id
    invocation.id
  end

  attributes(
    principal_label: { type: :string },
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

  type :string, optional: true
  def source
    invocation.source
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
