class AlertRoutingPolicySerializer < BaseSerializer
  object_as :policy

  type :string
  def id
    policy.id
  end

  attributes(
    enabled: { type: :boolean }
  )

  type :number
  def grouping_window_minutes
    policy.domain_config.fetch("grouping_window_minutes", AlertGroup::DEFAULT_WINDOW_MINUTES).to_i
  end

  type "string[]"
  def content_match_fields
    Array(policy.domain_config.fetch("content_match_fields", AlertGroup::DEFAULT_CONTENT_MATCH_FIELDS))
  end

  has_many :rules, serializer: PolicyRuleSerializer

  def rules
    policy.ordered_rules
  end
end
