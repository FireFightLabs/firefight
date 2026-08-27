class IncidentActionSerializer < BaseSerializer
  object_as :action

  type :string
  def id
    action.id
  end

  attributes(
    description: { type: :string },
    action_type: { type: '"action" | "followup"' },
    status: { type: '"open" | "in_progress" | "done"' }
  )

  # Whoever holds it, person or machine. The row marks a machine as one, so
  # it ships the same actor shape every other surface renders.
  has_one :assignee, serializer: ActorCompactSerializer, optional: true do
    action.assignee
  end

  has_one :created_by, serializer: ActorCompactSerializer do
    action.created_by
  end
end
