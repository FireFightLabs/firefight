class AlertSettingsSerializer < BaseSerializer
  object_as :alert

  type :string
  def id
    alert.id
  end

  attributes(
    status: { type: :string },
    routing_state: { type: :string },
    event_count: { type: :number }
  )

  type :string
  def title
    alert.title
  end

  type :string
  def source_id
    alert.alert_source_id
  end

  type :string
  def source_name
    alert.alert_source.name
  end

  type :string, optional: true
  def incident_id
    alert.incident_id
  end

  type :string, optional: true
  def incident_identifier
    alert.incident&.identifier
  end

  type :string, optional: true
  def matched_rule_id
    alert.matched_policy_rule_id
  end

  type :number, optional: true
  def matched_rule_priority
    alert.matched_policy_rule&.priority
  end

  # The alert source the matched rule's policy is scoped to; null means the
  # workspace default policy matched.
  type :string, optional: true
  def matched_rule_source_id
    alert.matched_policy_rule&.policy&.scoped_to_id
  end

  type :string
  def received_at
    alert.received_at.utc.iso8601
  end

  type :string
  def last_seen_at
    alert.last_seen_at.utc.iso8601
  end
end
