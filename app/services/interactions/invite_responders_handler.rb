module Interactions
  class InviteRespondersHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE

    def self.execute(interaction)
      workspace = interaction.workspace
      metadata = interaction.metadata
      incident = workspace.incidents.find(metadata.incident_id)

      user_ids = interaction.values.dig("invite_users_block", "invite_users_select", "selected_users") || []
      if user_ids.empty?
        return {
          response_action: "errors",
          errors: { invite_users_block: "Please select at least one responder" }
        }
      end

      result = IncidentInviteService.new(workspace).invite!(incident: incident, people: user_ids)
      workspace.adapter.post_invite_summary(
        channel_id: incident.channel_id, user_id: interaction.user_id, result: result
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
