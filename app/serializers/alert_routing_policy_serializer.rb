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
    policy.grouping_window_minutes
  end

  type "string[]"
  def content_match_fields
    policy.content_match_fields
  end

  has_many :rules, serializer: PolicyRuleSerializer

  def rules
    policy.ordered_rules
  end
end
