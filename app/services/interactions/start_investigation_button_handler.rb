module Interactions
  class StartInvestigationButtonHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_CREATE

    def self.execute(interaction)
      workspace = interaction.workspace
      incident = workspace.incidents.find(interaction.action_value)

      blocked = incident.investigation_blocked_reason
      return TerminalNotice.post(workspace, incident, interaction.user_id, blocked) if blocked

      refusal = Investigation.unavailable_reason(workspace)
      return tell(workspace, incident, interaction, refusal) if refusal

      started = InvestigationService.new(workspace).start(
        incident,
        trigger_source: Investigation::TRIGGER_BUTTON,
        triggered_by: workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)
      )
      return nil if started

      tell(workspace, incident, interaction, Investigation.already_running_message(incident))
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.warn({
        event: "interactions.start_investigation.record_missing",
        incident_id: interaction.action_value, error: e.message
      })
      nil
    end

    # These refusals are not the incident being over, so they are a plain ephemeral.
    private_class_method def self.tell(workspace, incident, interaction, text)
      workspace.adapter.post_ephemeral(
        channel_id: incident.channel_id, user_id: interaction.user_id, text: text
      )
      nil
    end
  end
end
