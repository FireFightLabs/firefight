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

      service = IncidentInviteService.new(workspace)
      result = service.invite!(incident: incident, user_ids: user_ids)
      workspace.adapter.post_ephemeral(
        channel_id: incident.channel_id,
        user_id: interaction.user_id,
        text: service.summary_message(result)
      )

      { response_action: "clear" }
    rescue ActiveRecord::RecordNotFound
      {
        response_action: "errors",
        errors: { invite_users_block: "Incident not found. Please try again." }
      }
    end
  end
end
