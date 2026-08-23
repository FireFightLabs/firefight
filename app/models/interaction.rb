class Interaction
  VIEW_SUBMISSION = "view_submission"
  BLOCK_ACTIONS = "block_actions"
  SHORTCUT = "shortcut"
  VIEW_CLOSED = "view_closed"

  attr_reader :type, :platform, :team_id, :user_id, :trigger_id,
              :channel_id, :action_id, :callback_id, :block_id,
              :selected_value, :selected_user, :action_value, :private_metadata,
              :view, :view_id, :values, :raw, :approval_id

  def initialize(attrs = {})
    attrs.each { |k, v| instance_variable_set(:"@#{k}", v) }
  end

  def workspace
    @workspace ||= Workspace.find_by!(platform: platform, platform_id: team_id)
  end

  # Who the Ability Gateway authorizes this interaction as. Provisioned on
  # demand so a first-time clicker is a principal like anyone else. nil when
  # the platform lookup fails and the dispatcher then refuses the call.
  def principal
    return @principal if defined?(@principal)

    @principal = WorkspaceMemberProvisioner.find_or_provision!(
      workspace: workspace, platform_user_id: user_id, adapter: workspace.adapter
    )
  rescue StandardError => e
    Rails.logger.warn({ event: "interaction.principal_unresolved", user_id: user_id, error: e.message }.to_json)
    @principal = nil
  end

  # What the approval digest is bound to. Deterministic and replayable. A
  # resumed interaction rebuilds the same hash, so the approval matches.
  def authorization_params
    {
      type: type,
      callback_id: callback_id,
      action_id: action_id,
      action_value: action_value,
      selected_value: selected_value,
      selected_user: selected_user,
      private_metadata: private_metadata,
      values: values
    }.compact
  end

  def incident_id
    Slack::PrivateMetadata.parse(private_metadata).incident_id
  rescue Slack::PrivateMetadata::InvalidError
    nil
  end

  # The attrs a resumed dispatch is rebuilt from, once an approval clears.
  # trigger_id is deliberately absent. It has long expired by then, and
  # nothing that opens a modal is gated.
  def resume_attrs
    {
      type: type, platform: platform, team_id: team_id, user_id: user_id,
      channel_id: channel_id, action_id: action_id, callback_id: callback_id,
      block_id: block_id, selected_value: selected_value, selected_user: selected_user,
      action_value: action_value, private_metadata: private_metadata,
      view_id: view_id, values: values
    }.compact
  end
end
