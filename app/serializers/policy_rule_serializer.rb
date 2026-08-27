class PolicyRuleSerializer < BaseSerializer
  object_as :rule

  # Union types built from the model constants so the generated TS carries
  # the real operator/action/target vocabulary instead of plain string.
  OPERATOR_UNION = PolicyRule::OPERATORS.map(&:inspect).join(" | ")
  ACTION_UNION = PolicyRule::AlertRoutingOutcome::ACTIONS.map(&:inspect).join(" | ")
  NOTIFY_TARGET_UNION = PolicyRule::AlertRoutingOutcome::NOTIFY_TARGET_TYPES.map(&:inspect).join(" | ")
  INVITE_TARGET_UNION = PolicyRule::AlertRoutingOutcome::INVITE_TARGET_TYPES.map(&:inspect).join(" | ")

  type :string
  def id
    rule.id
  end

  attributes(
    priority: { type: :number },
    enabled: { type: :boolean }
  )

  type "{ field: string; operator: #{OPERATOR_UNION}; value?: string | string[] }[]"
  def conditions
    rule.conditions
  end

  type "{ action: #{ACTION_UNION}; severityId?: string; notify?: { type: #{NOTIFY_TARGET_UNION}; channelId?: string; channelName?: string; memberId?: string; entryId?: string; of?: string }; invite?: { type: #{INVITE_TARGET_UNION}; memberId?: string; entryId?: string; of?: string }[] }"
  def outcome
    rule.outcome.deep_transform_keys { |key| key.to_s.camelize(:lower) }
  end
end
