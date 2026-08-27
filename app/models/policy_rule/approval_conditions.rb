# The approval rule dialog asks three questions (which abilities, which risk
# levels, which environments) and this is the mapping between those answers
# and the generic condition list the rule engine evaluates. An empty answer
# means no condition, so the rule matches everything on that axis.
module PolicyRule::ApprovalConditions
  FIELD_ACTION_KEY = "action_key"
  FIELD_RISK_LEVEL = "risk_level"
  FIELD_ENVIRONMENT = "environment"
  FIELDS = [ FIELD_ACTION_KEY, FIELD_RISK_LEVEL, FIELD_ENVIRONMENT ].freeze

  def self.build(action_keys: [], risk_levels: [], environments: [])
    {
      FIELD_ACTION_KEY => action_keys,
      FIELD_RISK_LEVEL => risk_levels,
      FIELD_ENVIRONMENT => environments
    }.filter_map do |field, values|
      values = Array(values).map(&:to_s).reject(&:blank?).uniq
      { "field" => field, "operator" => PolicyRule::OPERATOR_IS_ONE_OF, "value" => values } if values.any?
    end
  end

  def self.values_for(conditions, field)
    Array(conditions).filter_map do |condition|
      condition = condition.with_indifferent_access
      condition[:value] if condition[:field] == field && condition[:operator] == PolicyRule::OPERATOR_IS_ONE_OF
    end.flatten.map(&:to_s)
  end
end
