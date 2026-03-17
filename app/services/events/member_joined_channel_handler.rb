module Events
  class MemberJoinedChannelHandler
    def self.execute(platform, payload)
      event = payload["event"] || {}
      channel_id = event["channel"]
      user_id = event["user"]
      return unless channel_id && user_id

      workspace = Workspace.find_by(platform: platform, platform_id: payload["team_id"])
      return unless workspace
      return unless incident_related_channel?(workspace, channel_id)

      WorkspaceMemberProvisioner.find_or_provision!(
        workspace: workspace,
        platform_user_id: user_id,
        adapter: workspace.adapter
      )
    rescue StandardError => e
      Rails.logger.warn({
        event: "events.member_joined_channel.failed",
        error: e.message,
        team_id: payload["team_id"],
        channel: channel_id
      })
    end

    def self.incident_related_channel?(workspace, channel_id)
      return true if workspace.incidents_channel_id == channel_id

      workspace.incidents.active.in_channel(channel_id).exists?
    end
    private_class_method :incident_related_channel?
  end
end
