class WorkspaceSettingsSerializer < BaseSerializer
  object_as :workspace

  attributes(transcript_access_enabled: { type: :boolean })

  type :number, optional: true
  def transcript_retention_days
    workspace.transcript_retention_days
  end

  type :string
  def archive_channel_delay
    workspace.archive_channel_delay
  end
end
