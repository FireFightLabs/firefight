class WorkspaceSettingsSerializer < BaseSerializer
  object_as :workspace

  attributes(
    transcript_access_enabled: { type: :boolean },
    archive_channel_enabled: { type: :boolean },
    archive_channel_delay_minutes: { type: :number }
  )

  # Null keeps transcripts forever, which the screen says in words rather than
  # leaving the field empty and unexplained.
  type :number, optional: true
  def transcript_retention_days
    workspace.transcript_retention_days
  end
end
