module Interactions
  # Fix it on a pull request Halon opened that needs attention. The code change runs on its branch as whoever asked for
  # it, so only they may press it, and anyone else is told who can.
  class PullRequestFixHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_CREATE

    def self.execute(interaction)
      workspace = interaction.workspace
      notice = CodeAgentSession::Notice.find_by!(id: interaction.action_value, workspace_id: workspace.id)
      member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)
      refusal = PullRequestFollowing.fix!(notice, by: member)
      workspace.adapter.post_ephemeral(channel_id: interaction.channel_id, user_id: interaction.user_id, text: refusal) if refusal
      nil
    rescue ActiveRecord::RecordNotFound
      nil
    end
  end
end
