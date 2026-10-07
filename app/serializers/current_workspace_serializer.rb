class CurrentWorkspaceSerializer < BaseSerializer
  object_as :workspace

  type :string
  def id
    workspace.id.to_s
  end

  attributes(
    name: { type: :string },
    platform: { type: :string, optional: true }
  )

  type :boolean
  def chat_connected
    workspace.chat_connected?
  end

  # Every Declare button reads this, so none of them offers what the server would refuse.
  type :string, optional: true
  def incidents_blocked_reason
    workspace.incidents_blocked_reason
  end

  type :boolean
  def disconnected
    workspace.disconnected?
  end

  type :string, optional: true
  def avatar_url
    workspace.avatar_url
  end
end
