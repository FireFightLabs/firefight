class AbilityActionOptionSerializer < BaseSerializer
  object_as :action

  type :string
  def id
    action.id
  end

  attributes(
    key: { type: :string },
    kind: { type: :string },
    risk_level: { type: :string },
    reversible: { type: :boolean }
  )

  type :boolean
  def approval_exempt
    Ability::Action.approval_exempt?(action.key)
  end

  # Words for an action whose key does not say enough, nil for the rest.
  type :string, optional: true
  def title
    Ability::Action.described(action.key)&.fetch(:title)
  end

  type :string, optional: true
  def description
    Ability::Action.described(action.key)&.fetch(:description)
  end

  # Tool actions group under the connection that minted them. System actions
  # under Firefight itself.
  type :string
  def group
    action.system? ? "Firefight" : action.source&.integration&.name.to_s
  end
end
