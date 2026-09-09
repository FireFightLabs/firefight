# One person following the incident. The membership id keys the row, the
# chip inside renders the same way every other person on the page does.
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
