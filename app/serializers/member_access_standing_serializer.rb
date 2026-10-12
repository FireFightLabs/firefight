# Where a connection's read or changes pack stands for the members, as one dropdown of Who can do what shows it.
class MemberAccessStandingSerializer < BaseSerializer
  object_as :standing

  # The pack a change to this dropdown is saved to.
  type :string
  def pack_id
    standing.role.id
  end

  type Ability::Role::MemberAccess::CHOICES.map(&:inspect).join(" | ")
  def choice
    standing.choice
  end

  # The members holding it by a grant, when it is chosen people.
  type "string[]"
  def people_ids
    standing.people_ids
  end

  # Members kept from a read every member otherwise has, by a No access or a grant that lapsed.
  type "string[]"
  def left_out_ids
    standing.left_out_ids
  end

  # Members the row leaves out who still reach its tools through other access, by that access: a set or pack (id and
  # name), or abilities granted one by one (both null).
  type "{ permissionSetId: string | null; name: string | null; peopleIds: string[] }[]"
  def through
    standing.through.map { |access| { permissionSetId: access.role_id, name: access.role_name, peopleIds: access.people_ids } }
  end

  # Why there is nothing to choose, such as a connection with no tools that change anything, or nil.
  type :string, optional: true
  def unavailable_reason
    standing.role.member_access_unavailable_reason
  end
end
