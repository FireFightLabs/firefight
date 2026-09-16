# A thumbs press on a finding. The outcome is what the Learner reads later.
module Interactions
  class InvestigationFeedbackHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_READ

    def self.execute(interaction)
      finding_id, outcome = interaction.action_value.to_s.split(":")
      finding = Investigation::Finding.joins(:investigation)
        .where(investigations: { workspace_id: interaction.workspace.id }).find_by(id: finding_id)
      return unless finding && Investigation::Finding::OUTCOMES.include?(outcome)

      finding.record_outcome!(outcome, by: interaction.workspace.workspace_memberships.find_by(platform_user_id: interaction.user_id))
      nil
    end
  end
end
