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

  # nil when the team is not one Firefight knows, the same shape Command
  # gives so the controller and the dispatcher read one answer.
  def workspace
    return @workspace if defined?(@workspace)

    @workspace = Workspace.find_by(platform: platform, platform_id: team_id)
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

  UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

  # The modal's private_metadata, parsed once. Blank means a modal that
  # carries nothing. Malformed is logged and treated the same, so a bad
  # string never reaches a handler as a surprise.
  def metadata
    return @metadata if defined?(@metadata)

    @metadata = if private_metadata.blank?
      ModalState::EMPTY
    elsif private_metadata.to_s.match?(UUID)
      # A modal opened before every builder encoded its metadata. Safe to
      # drop once no such modal can still be open.
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
