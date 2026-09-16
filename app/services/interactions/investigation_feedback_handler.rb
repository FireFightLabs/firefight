# A thumbs press on a finding. The outcome is what the Learner reads later.
module Interactions
  class InvestigationFeedbackHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_READ

    def self.execute(interaction)
      finding_id, outcome = interaction.action_value.to_s.split(":")
      workspace = interaction.workspace
      finding = Investigation::Finding.in_workspace(workspace).find_by(id: finding_id)
      return unless finding && Investigation::Finding::OUTCOMES.include?(outcome)

      member = WorkspaceMemberProvisioner.find_or_provision!(
        workspace: workspace, platform_user_id: interaction.user_id, adapter: workspace.adapter
      )
      return unless member

      finding.record_verdict!(outcome, by: member)
      nil
    end
  end
end
