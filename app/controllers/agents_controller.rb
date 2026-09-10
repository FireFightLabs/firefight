# Agents are principals, so managing them is a permissions decision, not an API key one.
class AgentsController < InertiaController
  authorizes Ability::Action::RESOURCE_PERMISSIONS,
    read: :index,
    create: :create,
    update: %i[update rotate],
    delete: :destroy

  before_action :set_agent, only: %i[update destroy rotate]

  def index
    render inertia: "settings/agents", props: {
      agents: AgentSerializer.many(agent_roster)
    }
  end

  # A token is minted with the agent, since one without a credential can do nothing.
  def create
    agent, raw_token = ActiveRecord::Base.transaction do
      record = current_workspace.agents.create!(
        name: params.require(:name),
        slug: params.require(:slug),
        description: params[:description]
      )
      [ record, mint_token(record).last ]
    end

    flash.inertia[:api_key_token] = raw_token
    redirect_to gateway_agents_path, notice: "#{agent.name} was created."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to gateway_agents_path, inertia: { errors: e.record.errors.to_hash }
  end

  def update
    @agent.update!(params.permit(:name, :description, :enabled))

    redirect_to gateway_agents_path, notice: "#{@agent.name} was updated."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to gateway_agents_path, inertia: { errors: e.record.errors.to_hash }
  end

  # Rotation overlaps. The old token keeps working until revoked, so the agent stays up
  # while its config is updated.
  def rotate
    flash.inertia[:api_key_token] = mint_token(@agent).last

    redirect_to gateway_agents_path,
      notice: "A new token was issued. The old one still works until you revoke it."
  end

  def destroy
    @agent.destroy!

    redirect_to gateway_agents_path,
      notice: "#{@agent.name} was deleted. What it did stays on the timelines it touched."
  end

  private

  # Disabled agents stay listed. A hidden one still holds its slug and grants with no way back.
  def agent_roster
    current_workspace.agents.where(deleted_at: nil).ordered
      .includes(:api_keys, ability_grants: :action)
  end

  def set_agent
    @agent = current_workspace.agents.find(params[:id])
  end

  def mint_token(agent)
    ApiKey.create_with_token!(
      workspace: current_workspace,
      created_by: current_membership,
      agent: agent,
      name: "#{agent.name} token"
    )
  end
end
