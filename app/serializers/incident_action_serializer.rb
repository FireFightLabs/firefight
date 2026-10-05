class IncidentActionSerializer < BaseSerializer
  object_as :action

  type :string
  def id
    action.id
  end

  attributes(
    description: { type: :string },
    action_type: { type: '"action" | "followup"' },
    status: { type: '"open" | "in_progress" | "done"' },
    external_key: { type: :string, optional: true },
    external_url: { type: :string, optional: true }
  )

  # Person or machine, shipped as the actor shape every surface renders.
  has_one :assignee, serializer: ActorCompactSerializer, optional: true do
    action.assignee
  end

  has_one :created_by, serializer: ActorCompactSerializer do
    action.created_by
  end
end
