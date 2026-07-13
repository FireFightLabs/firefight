class AlertRoutingPolicySerializer < BaseSerializer
  object_as :policy

  type :string
  def id
    policy.id
  end

  attributes(
    enabled: { type: :boolean }
  )

  has_many :rules, serializer: PolicyRuleSerializer

  def rules
    policy.ordered_rules
  end
end
