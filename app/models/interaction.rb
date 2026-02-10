class Interaction
  VIEW_SUBMISSION = "view_submission"
  BLOCK_ACTIONS = "block_actions"
  SHORTCUT = "shortcut"
  VIEW_CLOSED = "view_closed"

  attr_reader :type, :team_id, :user_id, :trigger_id,
              :channel_id, :action_id, :callback_id,
              :selected_value, :view, :values, :raw

  def initialize(attrs = {})
    attrs.each { |k, v| instance_variable_set(:"@#{k}", v) }
  end

  def workspace
    @workspace ||= Workspace.find_by!(platform: Platforms::SLACK, platform_id: team_id)
  end
end
