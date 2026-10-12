# Who can do what in each connection, with the members who can be chosen for one.
class MemberAccessSerializer < BaseSerializer
  object_as :overview

  has_many :connections, serializer: ConnectionMemberAccessSerializer

  type "{ id: string; name: string }[]"
  def members
    overview.members.map { |member| { id: member.id, name: member.display_name } }
  end

  # Everyone in the workspace, admins included, so a workspace of one can say its choices are for people invited later.
  type :number
  def people_count
    overview.people_count
  end
end
