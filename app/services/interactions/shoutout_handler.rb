module Interactions
  class ShoutoutHandler
    def self.execute(interaction)
      workspace = interaction.workspace
      metadata = JSON.parse(interaction.private_metadata)
      incident = workspace.incidents.find(metadata["incident_id"])

      from_member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)
      recipient_user_id = interaction.values.dig("recipient_block", "recipient_select", "selected_user")
      to_member = if recipient_user_id
        WorkspaceMemberProvisioner.find_or_provision!(
          workspace: workspace,
          platform_user_id: recipient_user_id,
          adapter: workspace.adapter
        )
      end
      message = interaction.values.dig("message_block", "message_input", "value")

      shoutout = Shoutout.create!(
        incident: incident,
        from_member: from_member,
        to_member: to_member,
        message: message
      )

      result = workspace.adapter.post_shoutout_message(
        channel_id: incident.channel_id,
        incident: incident,
        from_user_id: interaction.user_id,
        recipient_user_id: recipient_user_id,
        message: message
      )
      shoutout.update_column(:slack_message_ts, result[:message_ts])

      nil
    rescue ActiveRecord::RecordNotFound, JSON::ParserError
      nil
    end
  end
end
