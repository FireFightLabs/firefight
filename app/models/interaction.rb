class Interaction
  VIEW_SUBMISSION = "view_submission"
  BLOCK_ACTIONS = "block_actions"
  SHORTCUT = "shortcut"
  VIEW_CLOSED = "view_closed"

  attr_reader :type, :platform, :team_id, :user_id, :trigger_id,
              :channel_id, :action_id, :callback_id, :block_id,
              :selected_value, :selected_user, :action_value, :private_metadata,
              :view, :view_id, :values, :raw, :approval_id, :prompt_handle

  def initialize(attrs = {})
    attrs.each { |k, v| instance_variable_set(:"@#{k}", v) }
  end

  # nil for an unknown team, the same shape Command gives.
  def workspace
    return @workspace if defined?(@workspace)

    @workspace = Workspace.find_by(platform: platform, platform_id: team_id)
  end

  # What the approval digest is bound to. A resumed interaction rebuilds the
  # same hash, so the approval matches.
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

  UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

  # Malformed metadata is logged and treated as blank, so a bad string never
  # reaches a handler.
  def metadata
    return @metadata if defined?(@metadata)

    @metadata = if private_metadata.blank?
      ModalState::EMPTY
    elsif private_metadata.to_s.match?(UUID)
      # A modal opened before every builder encoded its metadata.
      ModalState::Result.new(incident_id: private_metadata.to_s)
    else
      ModalState.parse(private_metadata)
    end
  rescue ModalState::InvalidError => e
    Rails.logger.warn({ event: "interaction.private_metadata_invalid", callback_id: callback_id, error: e.message }.to_json)
    @metadata = ModalState::EMPTY
  end

  def incident_id
    metadata.incident_id
  end

  # trigger_id is left out on purpose. It has expired by the time an approval
  # clears, and nothing that opens a modal is gated.
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
