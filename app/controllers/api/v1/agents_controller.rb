# Authorizes as permissions, which is admin-only and ungrantable, so an agent
# can never create or re-credential another agent whatever it holds. The MCP
# tools are the siblings of these.
class Api::V1::AgentsController < Api::V1::ApiController
  before_action :set_agent, only: %i[update destroy rotate revoke_token]

  def index
    authorize!(Ability::Action::RESOURCE_PERMISSIONS, Ability::Action::ACTION_READ)

    @agents = agent_scope.ordered.includes(:api_keys, ability_grants: :action)
  end

  # One token comes with the agent, since an agent without a credential can do
  # nothing and making that a second call is a call everyone forgets.
  def create
    authorize!(Ability::Action::RESOURCE_PERMISSIONS, Ability::Action::ACTION_CREATE)

    ActiveRecord::Base.transaction do
      @agent = current_workspace.agents.create!(
        name: params.require(:name),
        slug: params[:slug].presence || params.require(:name).parameterize(separator: "_"),
        description: params[:description]
      )
      @token = mint_token
    end

    render :show, status: :created
  end

  def update
    authorize!(Ability::Action::RESOURCE_PERMISSIONS, Ability::Action::ACTION_UPDATE)

    @agent.update!({ name: params[:name], description: params[:description], enabled: params[:enabled] }.compact)

    render :show
  end

  # An overlap, not a swap. The old token keeps working until it is revoked, so
  # the agent stays up while its configuration is updated.
  def rotate
    authorize!(Ability::Action::RESOURCE_PERMISSIONS, Ability::Action::ACTION_UPDATE)

    @token = mint_token

    @agent.reload
    render :show, status: :created
  end

  def revoke_token
    authorize!(Ability::Action::RESOURCE_PERMISSIONS, Ability::Action::ACTION_DELETE)

    token = @agent.live_api_keys.find { |key| key.token_prefix == params[:token_prefix] }
    raise ActiveRecord::RecordNotFound unless token

    token.soft_delete!
    head :no_content
  end

  def destroy
    authorize!(Ability::Action::RESOURCE_PERMISSIONS, Ability::Action::ACTION_DELETE)

    @agent.destroy!
    head :no_content
  end

  private

  def mint_token
    ApiKey.create_with_token!(
      workspace: current_workspace,
      created_by: Current.principal,
      agent: @agent,
      name: "#{@agent.name} token"
    ).last
  end

  def agent_scope
    current_workspace.agents.where(deleted_at: nil)
  end

  def set_agent
    @agent = agent_scope.find_by!(slug: params[:id])
  end
end
