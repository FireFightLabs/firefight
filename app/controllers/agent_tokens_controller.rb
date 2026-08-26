# Revoking one of an agent's tokens. Rotation leaves two live at once, so the
# old one needs a way out that does not touch the agent or its grants.
class AgentTokensController < InertiaController
  authorizes Ability::Action::RESOURCE_PERMISSIONS, delete: :destroy

  def destroy
    agent = current_workspace.agents.find(params[:agent_id])
    token = agent.api_keys.where(deleted_at: nil).find(params[:id])
    token.soft_delete!

    redirect_to gateway_agents_path, notice: "That token was revoked. #{remaining_notice(agent)}"
  end

  private

  def remaining_notice(agent)
    return "#{agent.name} has no working token left, so it cannot act." unless agent.reload.credentialed?

    "#{agent.name} keeps working on its other token."
  end
end
