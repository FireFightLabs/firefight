module Interactions
  # Run again on a question that stopped on our side. The new run asks the same question in the same place, as whoever
  # pressed it, since they are the one asking now.
  class RerunInvestigationQuestionHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_CREATE

    def self.execute(interaction)
      workspace = interaction.workspace
      original = workspace.investigations.seen.find(interaction.action_value)

      refusal = Investigation.start_refusal(workspace)
      return tell(workspace, original, interaction, refusal) if refusal

      InvestigationService.new(workspace).start(
        nil,
        trigger_source: Investigation::TRIGGER_BUTTON,
        triggered_by: workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id),
        brief: original.brief,
        channel_id: original.channel_id
      )
      nil
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.warn({ event: "interactions.rerun_investigation_question.record_missing", investigation_id: interaction.action_value, error: e.message })
      nil
    end

    private_class_method def self.tell(workspace, original, interaction, text)
      workspace.adapter.post_ephemeral(channel_id: original.channel_id, user_id: interaction.user_id, text: text)
      nil
    end
  end
end
