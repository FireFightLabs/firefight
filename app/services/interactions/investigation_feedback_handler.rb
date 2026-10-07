# A rating pressed on a finding, right, partly right or wrong. The outcome is what the Learner reads later.
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
      confirm(workspace, interaction, outcome)
      nil
    end

    # Slack's thumbs show what was pressed themselves. A plain button does not, so its press is answered.
    def self.confirm(workspace, interaction, outcome)
      return if interaction.action_id == Identifiers::INVESTIGATION_FEEDBACK || interaction.prompt_handle.blank?

      workspace.adapter.answer_privately(prompt_handle: interaction.prompt_handle, text: Investigation::Finding.verdict_recorded(outcome))
    rescue AdapterError => e
      Rails.logger.warn({ event: "interactions.investigation_feedback.unconfirmed", error: e.class.name }.to_json)
    end
    private_class_method :confirm
  end
end
