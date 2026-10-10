module Interactions
  # Schedule, Cancel, Retry or Undo on a plan Halon keeps in a chat, from its message in Slack. Whoever may press them on
  # the dashboard may here, and a press someone may not make is answered privately with why. The message redraws itself
  # once the plan moves.
  class ChatPlanHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_CREATE

    def self.execute(interaction)
      workspace = interaction.workspace
      plan = Chat::Plan.where(workspace_id: workspace.id).find(interaction.action_value)
      member = WorkspaceMemberProvisioner.find_or_provision!(workspace: workspace, platform_user_id: interaction.user_id, adapter: workspace.adapter)

      refusal = case interaction.action_id
      when Identifiers::CHAT_PLAN_SCHEDULE then Conversation::Plans.approve!(plan, by: member)
      when Identifiers::CHAT_PLAN_CANCEL then Conversation::Plans.cancel!(plan, by: member)
      when Identifiers::CHAT_PLAN_RETRY then Conversation::Plans.retry!(plan, by: member)
      else Conversation::Plans.undo!(plan, by: member)
      end
      workspace.adapter.post_ephemeral(channel_id: interaction.channel_id, user_id: interaction.user_id, text: refusal) if refusal
      nil
    rescue ActiveRecord::RecordNotFound
      nil
    end
  end
end
