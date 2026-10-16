module Interactions
  # Details on an approval request opens the call it is for, which its card keeps off it. trigger_id expires in three
  # seconds, so this stays sync.
  class OpenApprovalDetailsHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_APPROVALS

    def self.execute(interaction)
      workspace = interaction.workspace
      approval = workspace.ability_approvals.find_by(id: interaction.action_value)
      return unless approval

      workspace.adapter.open_approval_details(trigger_id: interaction.trigger_id, approval: approval)
      nil
    rescue AdapterError::TriggerExpired
      nil
    end
  end
end
