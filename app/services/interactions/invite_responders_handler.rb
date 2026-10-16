module Interactions
  class InviteRespondersHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE

    def self.execute(interaction)
      workspace = interaction.workspace
      metadata = interaction.metadata
      incident = workspace.incidents.find(metadata.incident_id)

      adapter = workspace.adapter
      user_ids = adapter.submitted_value(values: interaction.values, block_id: Identifiers::INVITE_USERS_BLOCK, input_id: Identifiers::INVITE_USERS_SELECT, kind: PlatformAdapter::Input::USERS) || []
      if user_ids.empty?
        return adapter.modal_errors_response({ Identifiers::INVITE_USERS_BLOCK => "Please select at least one responder" })
      end

      result = IncidentInviteService.new(workspace).invite!(incident: incident, people: user_ids)
      adapter.post_invite_summary(
        channel_id: incident.channel_id, user_id: interaction.user_id, result: result
      )

      adapter.modal_close_response
    rescue ActiveRecord::RecordNotFound
      workspace.adapter.modal_errors_response({ Identifiers::INVITE_USERS_BLOCK => "Incident not found. Please try again." })
    end
  end
end
