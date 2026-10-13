module Interactions
  # Stays sync, trigger_id expires in 3s.
  class RunRunbookHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_WORKFLOWS, Ability::Action::ACTION_CREATE

    def self.execute(interaction)
      workspace = interaction.workspace
      adapter = workspace.adapter
      incident_runbook = workspace.incident_runbooks.find(interaction.action_value)
      member = WorkspaceMemberProvisioner.find_or_provision!(workspace: workspace, platform_user_id: interaction.user_id, adapter: adapter)

      blocked = incident_runbook.runbook.run_blocked_reason(member)
      if blocked
        adapter.post_ephemeral(channel_id: incident_runbook.incident.channel_id, user_id: interaction.user_id, text: blocked)
      else
        adapter.open_runbook_run_modal(trigger_id: interaction.trigger_id, incident_runbook: incident_runbook, push: interaction.view_id.present?)
      end
      nil
    rescue ActiveRecord::RecordNotFound
      nil
    end
  end
end
