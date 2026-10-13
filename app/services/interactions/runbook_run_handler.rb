module Interactions
  class RunbookRunHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_WORKFLOWS, Ability::Action::ACTION_CREATE

    def self.execute(interaction)
      workspace = interaction.workspace
      adapter = workspace.adapter
      incident_runbook = workspace.incident_runbooks.find(interaction.metadata.incident_runbook_id)
      member = WorkspaceMemberProvisioner.find_or_provision!(workspace: workspace, platform_user_id: interaction.user_id, adapter: adapter)
      incident = incident_runbook.incident

      run = RunbookRunService.new(incident_runbook.runbook).start!(by: member, inputs: adapter.runbook_run_inputs(values: interaction.values), incident: incident)
      adapter.post_runbook_run_started(channel_id: incident.channel_id, user_id: interaction.user_id, run: run)
      nil
    rescue Workflow::Run::Refused => refused
      adapter.runbook_run_refused(refused.message)
    rescue ActiveRecord::RecordNotFound
      adapter.runbook_run_refused("That runbook is no longer attached to this incident.")
    end
  end
end
