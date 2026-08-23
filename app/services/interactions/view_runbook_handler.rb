module Interactions
  # Stays sync, trigger_id expires in 3s.
  class ViewRunbookHandler
    extend HandlerAuthorization
    authorize_as ApiKey::RESOURCE_RUNBOOKS

    def self.execute(interaction)
      workspace = interaction.workspace
      incident_runbook = workspace.incident_runbooks.find(interaction.action_value)

      workspace.adapter.open_modal(
        trigger_id: interaction.trigger_id,
        view: Slack::Modals::RunbookDetail.build(incident_runbook)
      )

      nil
    rescue ActiveRecord::RecordNotFound
      nil
    end
  end
end
