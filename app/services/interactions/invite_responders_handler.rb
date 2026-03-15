module Interactions
  class InviteRespondersHandler
    def self.execute(interaction)
      workspace = interaction.workspace
      incident = workspace.incidents.find(interaction.private_metadata)

      user_ids = interaction.values.dig("invite_users_block", "invite_users_select", "selected_users") || []
      if user_ids.empty?
        return {
          response_action: "errors",
          errors: { invite_users_block: "Please select at least one responder" }
        }
      end

      result = IncidentInviteService.new(workspace).invite!(incident: incident, user_ids: user_ids)
      workspace.adapter.post_ephemeral(
        channel_id: incident.channel_id,
        user_id: interaction.user_id,
        text: summary_message(result)
      )

      { response_action: "clear" }
    rescue ActiveRecord::RecordNotFound
      {
        response_action: "errors",
        errors: { invite_users_block: "Incident not found. Please try again." }
      }
    end

    private_class_method def self.summary_message(result)
      invited_count = result[:invited_user_ids].size
      already_count = result[:already_in_channel_user_ids].size
      failed_count = result[:failed_invites].size

      parts = []
      parts << "Invited #{invited_count} responder#{'s' unless invited_count == 1}." if invited_count.positive?
      parts << "#{already_count} already in channel." if already_count.positive?
      parts << "#{failed_count} failed." if failed_count.positive?
      parts = [ "No responders were invited." ] if parts.empty?

      parts.join(" ")
    end
  end
end
