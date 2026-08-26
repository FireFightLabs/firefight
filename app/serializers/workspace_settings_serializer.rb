class WorkspaceSettingsSerializer < BaseSerializer
  object_as :workspace

  attributes(transcript_access_enabled: { type: :boolean })

  type :number, optional: true
  def transcript_retention_days
    workspace.transcript_retention_days
  end
end
