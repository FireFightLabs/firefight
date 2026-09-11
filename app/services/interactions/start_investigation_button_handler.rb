module Interactions
  class StartInvestigationButtonHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_CREATE

    def self.execute(interaction)
      workspace = interaction.workspace
      incident = workspace.incidents.find(interaction.action_value)

      refusal = Investigation.unavailable_reason(workspace) || incident.investigation_blocked_reason
      return TerminalNotice.post(workspace, incident, interaction.user_id, refusal) if refusal

      service = InvestigationService.new(workspace)
      if service.live_for(incident)
        return TerminalNotice.post(
          workspace, incident, interaction.user_id,
          "Already investigating #{incident.identifier}, I will post here when I have something."
        )
      end

      service.start(
        incident,
        trigger_source: Investigation::TRIGGER_BUTTON,
        triggered_by: workspace.workspace_memberships.find_by(platform_user_id: interaction.user_id)
      )
      nil
    rescue ActiveRecord::RecordNotFound
      Rails.logger.warn({
        event: "investigation.button_incident_missing", incident_id: interaction.action_value
      }.to_json)
      nil
    end
  end
end
