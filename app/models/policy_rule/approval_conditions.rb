# Maps the dialog's answers to the condition list the rule engine evaluates.
# An empty answer means no condition, so the rule matches everything on that axis.
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

  # A read never waits for approval, so a rule naming the read risk level or an ability that only reads would hold
  # nothing, and is refused with why rather than saved to look as if it did. A rule saved before this keeps working for
  # the changes it names.
  def self.errors_for(conditions, workspace:)
    return [] unless conditions.is_a?(Array) && conditions.all?(Hash)

    errors = []
    if values_for(conditions, FIELD_RISK_LEVEL).include?(Ability::Action::RISK_READ)
      errors << "Reads never wait for approval, so a rule cannot hold the read risk level. Pick write or destructive."
    end
    reads = Ability::Action.where(workspace_id: [ nil, workspace&.id ], key: values_for(conditions, FIELD_ACTION_KEY)).select(&:read?).map(&:key)
    if reads.any?
      errors << "#{reads.sort.to_sentence} only #{reads.one? ? 'reads' : 'read'}, and reads never wait for approval. Leave #{reads.one? ? 'it' : 'them'} out of the rule."
    end
    errors
  end

  def self.values_for(conditions, field)
    Array(conditions).filter_map do |condition|
      condition = condition.with_indifferent_access
      condition[:value] if condition[:field] == field && condition[:operator] == PolicyRule::OPERATOR_IS_ONE_OF
    end.flatten.map(&:to_s)
  end
end
