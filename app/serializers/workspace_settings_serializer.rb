class WorkspaceSettingsSerializer < BaseSerializer
  object_as :workspace

  ISSUE_CREATION_UNION = Workspace::IssueSync::ISSUE_CREATIONS.map(&:inspect).join(" | ")

  attributes(transcript_access_enabled: { type: :boolean }, web_search_enabled: { type: :boolean }, halon_regression_enabled: { type: :boolean })

  # The connected team's own name in Slack, or null while the workspace has no Slack.
  type :string, optional: true
  def chat_team_name
    workspace.chat_team_name
  end

  type :number, optional: true
  def transcript_retention_days
    workspace.transcript_retention_days
  end

  # Days an unconfirmed memory waits for a person before Halon stops using it, or null to use it until someone decides.
  type :number, optional: true
  def memory_expiry_days
    workspace.memory_expiry_days
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

  # The slug of the connection to the tracker items are kept in step with, or null while there is none.
  type :string, optional: true
  def issue_tracker
    workspace.issue_tracker
  end

  # No tracker first, as null, then each connection to a tracker that keeps items in step, with where its new issues go
  # and how to send its webhook to Firefight.
  type "{ value: string | null; label: string; fields: { key: string; label: string; placeholder: string; hint: string; required: boolean }[]; steps: string[] }[]"
  def issue_trackers
    workspace.issue_tracker_choices.map { |choice| choice.to_h.merge(fields: choice.fields.map(&:to_h)) }
  end

  type ISSUE_CREATION_UNION
  def issue_creation
    workspace.issue_creation
  end

  type "{ value: #{ISSUE_CREATION_UNION}; label: string }[]"
  def issue_creations
    Workspace::IssueSync::ISSUE_CREATION_CHOICES.map(&:to_h)
  end

  # What was saved for each of the chosen tracker's fields.
  type "Record<string, string>"
  def issue_tracker_target
    workspace.issue_tracker_target
  end

  # The secret itself is never sent back.
  type :boolean
  def issue_webhook_secret_set
    workspace.issue_webhook_secret_set?
  end

  type :string, optional: true
  def issue_creation_blocked_reason
    workspace.issue_creation_blocked_reason
  end

  # Whether Firefight registers the chosen connection's webhook itself, which a connection made with its own app does,
  # so the setting asks for no steps and no secret.
  type :boolean
  def issue_webhook_automatic
    connection = workspace.issue_sync_connection
    connection.present? && Integrations::Issues.registers_webhooks?(connection)
  end

  type :boolean
  def issue_webhook_registered
    workspace.issue_webhook_registered?
  end

  type :string, optional: true
  def issue_webhook_blocked_reason
    workspace.issue_webhook_blocked_reason
  end
end
