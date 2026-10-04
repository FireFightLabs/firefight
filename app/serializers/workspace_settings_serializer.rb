class WorkspaceSettingsSerializer < BaseSerializer
  object_as :workspace

  attributes(transcript_access_enabled: { type: :boolean }, web_search_enabled: { type: :boolean }, halon_regression_enabled: { type: :boolean })

  type :number, optional: true
  def transcript_retention_days
    workspace.transcript_retention_days
  end

  type :string
  def archive_channel_delay
    workspace.archive_channel_delay
  end

  # The slug of the connected coding agent that writes code fixes, or null while Firefight's own agent does.
  type :string, optional: true
  def code_fix_agent
    workspace.code_fix_agent
  end

  # Firefight's own agent first, as null, then each coding agent connected to the workspace.
  type "{ value: string | null; label: string }[]"
  def code_fix_agents
    workspace.code_fix_agent_choices.map(&:to_h)
  end

  type :string, optional: true
  def code_fix_agent_blocked_reason
    workspace.code_fix_agent_blocked_reason
  end
end
