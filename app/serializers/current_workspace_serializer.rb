class CurrentWorkspaceSerializer < BaseSerializer
  object_as :workspace

  type :string
  def id
    workspace.id.to_s
  end

  attributes(
    name: { type: :string },
    platform: { type: :string }
  )

  type :boolean
  def disconnected
    workspace.disconnected?
  end

  type :string, optional: true
  def avatar_url
    workspace.avatar_url
  end
end
