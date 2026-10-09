module Interactions
  # Undo fix on a fix's progress, after the platform's own confirm. Halon writes the undo, which is posted in the thread to apply
  # like the fix. Who may start a run may ask for it, and only the clicker is told what happens.
  class UndoFixHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_CREATE

    def self.execute(interaction)
      workspace = interaction.workspace
      plan = Investigation::RemediationPlan.in_workspace(workspace).find(interaction.action_value)
      member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)

      said = Investigation::UndoWriter.request!(plan, by: member) || Investigation::UndoWriter::WRITING
      workspace.adapter.post_ephemeral(channel_id: interaction.channel_id, user_id: interaction.user_id, text: said)
      nil
    rescue ActiveRecord::RecordNotFound
      nil
    end
  end
end
