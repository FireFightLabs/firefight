# A member's request for a pack, waiting on an admin, on the Permissions screen.
class PackRequestSerializer < BaseSerializer
  object_as :request

  type :string
  def id
    request.id
  end

  type :string
  def requester_name
    request.requester.display_name
  end

  type :string
  def pack_name
    request.role.name
  end

  type :string, optional: true
  def pack_description
    request.role.description
  end

  type :string
  def requested_at
    request.requested_at.utc.iso8601
  end

  type :string, optional: true
  def give_blocked_reason
    request.give_blocked_reason
  end
end
