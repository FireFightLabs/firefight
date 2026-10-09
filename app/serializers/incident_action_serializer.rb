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

  # What a person reads about its issue while it is missing or not kept in step, or null.
  type :string, optional: true
  def issue_status
    action.issue_status_text
  end

  # Whether Firefight is opening its issue now, so the page looks again until it is there.
  type :boolean
  def issue_opening
    action.issue_opening?
  end

  # Whether its issue was asked for and is missing, so the control offers to try again.
  type :boolean
  def issue_missing
    action.issue_missing?
  end

  # Whether the item offers Create issue at all.
  type :boolean
  def issue_request_offered
    action.issue_request_offered?
  end

  # Why Create issue cannot be used now, or null when it can.
  type :string, optional: true
  def issue_request_blocked_reason
    action.issue_request_offered? ? action.issue_request_blocked_reason : nil
  end

  # Person or machine, shipped as the actor shape every surface renders.
  has_one :assignee, serializer: ActorCompactSerializer, optional: true do
    action.assignee
  end

  has_one :created_by, serializer: ActorCompactSerializer do
    action.created_by
  end
end
