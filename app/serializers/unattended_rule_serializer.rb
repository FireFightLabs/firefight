class UnattendedRuleSerializer < BaseSerializer
  object_as :rule

  CAPABILITY_UNION = Ability::UnattendedRule::CAPABILITIES.map(&:inspect).join(" | ")

  type :string
  def id = rule.id

  type CAPABILITY_UNION
  def capability = rule.capability

  type :string
  def resource_id = rule.resource_id

  type :string
  def resource_name = rule.resource.name

  type :string
  def metric = rule.metric

  type :number
  def threshold = rule.threshold.to_f

  attributes(minutes: { type: :number }, enabled: { type: :boolean })

  # The rule as a person reads it, the same words Halon uses in the incident when it acts under it.
  type :string
  def sentence = rule.sentence

  type :string, optional: true
  def created_by_name = rule.created_by&.display_name

  # How many changes Halon made under it.
  type :number
  def usage_count = rule.usage_count

  # Why it cannot act now, such as Halon holding no grant of the tool, shown on the row.
  type :string, optional: true
  def blocked_reason = rule.blocked_reason

  type :string, optional: true
  def delete_blocked_reason = rule.delete_blocked_reason
end
