class IncidentSubscriberSerializer < BaseSerializer
  object_as :membership

  type :string
  def id
    membership.id
  end

  has_one :workspace_membership, as: :member, serializer: ActorCompactSerializer do
    membership
  end
end
