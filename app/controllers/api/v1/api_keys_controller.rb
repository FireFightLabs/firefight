# Service keys over REST, matching upsert_api_key and delete_api_key on MCP.
# Authorizes as api_keys, which is admin-only and ungrantable, so a personal
# token belonging to an admin reaches this and no machine ever can.
#
# Personal tokens are left out on purpose: they belong to the person who minted
# them, not to the workspace.
class Api::V1::ApiKeysController < Api::V1::ApiController
  before_action :set_api_key, only: %i[update destroy]

  def index
    authorize!(Ability::Action::RESOURCE_API_KEYS, Ability::Action::ACTION_READ)

    @api_keys = key_scope.ordered
  end

  # The token appears once, here, and never in a listing.
  def create
    authorize!(Ability::Action::RESOURCE_API_KEYS, Ability::Action::ACTION_CREATE)

    ActiveRecord::Base.transaction do
      @api_key, @token = ApiKey.create_with_token!(
        workspace: current_workspace, created_by: Current.principal, name: params.require(:name)
      )
      @api_key.replace_permissions!(permissions) if params.key?(:permissions)
    end

    @api_key.reload
    render :show, status: :created
  end

  # Sending permissions replaces the set rather than adding to it.
  def update
    authorize!(Ability::Action::RESOURCE_API_KEYS, Ability::Action::ACTION_UPDATE)

    ActiveRecord::Base.transaction do
      @api_key.update!({ name: params[:name], active: params[:active] }.compact)
      @api_key.replace_permissions!(permissions) if params.key?(:permissions)
    end

    @api_key.reload
    render :show
  end

  def destroy
    authorize!(Ability::Action::RESOURCE_API_KEYS, Ability::Action::ACTION_DELETE)

    @api_key.soft_delete!
    head :no_content
  end

  private

  def permissions
    params[:permissions].respond_to?(:to_unsafe_h) ? params[:permissions].to_unsafe_h : params[:permissions].to_h
  end

  def key_scope
    current_workspace.api_keys.where(deleted_at: nil).service
  end

  def set_api_key
    @api_key = key_scope.find_by!(token_prefix: params[:id])
  end
end
