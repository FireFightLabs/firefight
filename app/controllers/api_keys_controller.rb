class ApiKeysController < InertiaController
  before_action :require_authentication
  before_action :set_api_key, only: [ :update, :destroy ]

  def create
    member = current_workspace.workspace_memberships.find_by!(user: current_user)

    api_key, raw_token = ApiKey.create_with_token!(
      workspace: current_workspace,
      created_by: member,
      name: params.require(:name),
      permissions: params[:permissions]&.to_unsafe_h || {},
      expires_at: params[:expires_at].present? ? Time.zone.parse(params[:expires_at]) : nil
    )

    redirect_to settings_path(tab: "api-keys"),
      flash: { api_key_token: raw_token }
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: settings_path(tab: "api-keys"),
      inertia: { errors: e.record.errors.to_hash }
  end

  def update
    @api_key.update!(
      name: params[:name],
      permissions: params[:permissions]&.to_unsafe_h || @api_key.permissions,
      active: ActiveModel::Type::Boolean.new.cast(params[:active])
    )
    redirect_to settings_path(tab: "api-keys")
  end

  def destroy
    @api_key.soft_delete!
    redirect_to settings_path(tab: "api-keys")
  end

  private

  def set_api_key
    @api_key = current_workspace.api_keys.where(deleted_at: nil).find(params[:id])
  end
end
