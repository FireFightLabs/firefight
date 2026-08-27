module Events
  class MemberJoinedChannelHandler
    def self.execute(workspace, payload)
      event = payload["event"] || {}
      channel_id = event["channel"]
      user_id = event["user"]
      return unless channel_id && user_id
      return unless incident_related_channel?(workspace, channel_id)

      WorkspaceMemberProvisioner.find_or_provision!(
        workspace: workspace,
        platform_user_id: user_id,
        adapter: workspace.adapter
      )
    end

    def self.incident_related_channel?(workspace, channel_id)
      return true if workspace.incidents_channel_id == channel_id

      workspace.incidents.active.in_channel(channel_id).exists?
    end
    private_class_method :incident_related_channel?
  end
end
