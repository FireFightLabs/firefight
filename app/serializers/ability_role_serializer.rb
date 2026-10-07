class AbilityRoleSerializer < BaseSerializer
  object_as :role

  type :string
  def id
    role.id
  end

  attributes(
    name: { type: :string },
    slug: { type: :string },
    description: { type: :string, optional: true }
  )

  # A built-in pack Firefight keeps in step with the connections, which nobody edits or deletes by hand.
  type :boolean
  def built_in
    role.built_in?
  end

  type :string, optional: true
  def pack
    role.pack
  end

  type :string, optional: true
  def edit_blocked_reason
    role.edit_blocked_reason
  end

  type :string, optional: true
  def delete_blocked_reason
    role.delete_blocked_reason
  end

  type "string[]"
  def action_ids
    role.role_actions.map(&:action_id)
  end

  type :number
  def grant_count
    role.grants.size
  end
end
