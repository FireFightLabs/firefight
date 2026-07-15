class PolicyRuleSerializer < BaseSerializer
  object_as :rule

  type :string
  def id
    rule.id
  end

  attributes(
    priority: { type: :number },
    enabled: { type: :boolean }
  )

  type "{ field: string; operator: string; value?: string | string[] }[]"
  def conditions
    rule.conditions
  end

  type "{ action: string; severityId?: string; notify?: { type: string; channelId?: string; memberId?: string; entryId?: string; of?: string }; invite?: { type: string; memberId?: string; entryId?: string; of?: string }[] }"
  def outcome
    rule.outcome.deep_transform_keys { |key| key.to_s.camelize(:lower) }
  end
end
