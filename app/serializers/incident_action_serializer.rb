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

  type :string, optional: true
  def assignee
    action.assignee&.user&.name
  end

  type :string, optional: true
  def assignee_avatar_url
    action.assignee&.user&.avatar_url
  end

  type :string
  def created_by
    action.created_by.user.name
  end
end
