class PolicyRuleSerializer < BaseSerializer
  object_as :rule

  type :string
  def id
    rule.id
  end

  attributes(
    priority: { type: :number }
  )

  type "{ field: string; operator: string; value?: string | string[] }[]"
  def conditions
    rule.conditions
  end

  type "{ action: string; severityId?: string; channel?: string; channelContextKey?: string }"
  def outcome
    rule.outcome.transform_keys { |key| key.to_s.camelize(:lower) }
  end
end
