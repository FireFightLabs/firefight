# One connection's row of Who can do what: what members can read through it and what they can change.
class ConnectionMemberAccessSerializer < BaseSerializer
  object_as :connection

  type :string
  def id
    connection.integration.id
  end

  # Named as the Permissions screen names the connection's packs.
  type :string
  def name
    connection.integration.display_name
  end

  has_one :read, serializer: MemberAccessStandingSerializer
  has_one :change, serializer: MemberAccessStandingSerializer
end
