module Interactions
  # Stays sync, trigger_id expires in 3s.
  class ViewRunbookHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_RUNBOOKS

    def self.execute(interaction)
      workspace = interaction.workspace
      incident_runbook = workspace.incident_runbooks.find(interaction.action_value)

      adapter = workspace.adapter
      adapter.open_modal(
        trigger_id: interaction.trigger_id,
        view: adapter.build_modal(PlatformAdapter::Modal::RUNBOOK_DETAIL, incident_runbook)
      )

      nil
    rescue ActiveRecord::RecordNotFound
      nil
    end
  end
end
