class AbilityRoleSerializer < BaseSerializer
  object_as :role

  type :string
  def id
    role.id
  end

  attributes(
    name: { type: :string },
    slug: { type: :string }
  )

  type "string[]"
  def action_ids
    role.role_actions.map(&:action_id)
  end

  type :number
  def grant_count
    role.grants.size
  end
end
