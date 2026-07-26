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

  # Tool actions group under the connection that minted them; system actions
  # under Firefight itself.
  type :string
  def group
    action.system? ? "Firefight" : action.source&.integration&.name.to_s
  end
end
