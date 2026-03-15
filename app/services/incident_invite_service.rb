class IncidentInviteService
  def initialize(workspace)
    @workspace = workspace
    @adapter = workspace.adapter
  end

  def invite!(incident:, user_ids:)
    invited_user_ids = []
    already_in_channel_user_ids = []
    failed_invites = []

    normalized_user_ids(user_ids).each do |user_id|
      begin
        @adapter.invite_user(channel_id: incident.channel_id, user_id: user_id)
        invited_user_ids << user_id
      rescue AdapterError => e
        if already_in_channel_error?(e)
          already_in_channel_user_ids << user_id
        else
          failed_invites << { user_id: user_id, error: e.message }
        end
      end
    end

    {
      invited_user_ids: invited_user_ids,
      already_in_channel_user_ids: already_in_channel_user_ids,
      failed_invites: failed_invites
    }
  end

  private

  def normalized_user_ids(user_ids)
    Array(user_ids).compact.map(&:to_s).uniq
  end

  def already_in_channel_error?(error)
    message = error.message.to_s
    message.include?("already_in_channel") || message.include?("cant_invite_self")
  end
end
