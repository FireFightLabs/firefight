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

    flash.inertia[:api_key_token] = raw_token
    redirect_to settings_api_keys_path
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: settings_api_keys_path,
      inertia: { errors: e.record.errors.to_hash }
  end

  # Only touch fields the client explicitly passes. Without these guards,
  # sending `permissions: {}` would wipe permissions (`{}` is truthy so the
  # old `||` fallback never triggered) and omitting `active` would write nil
  # into a NOT NULL column.
  def update
    attrs = {}
    attrs[:name] = params[:name] if params.key?(:name)
    attrs[:permissions] = params[:permissions].to_unsafe_h if params.key?(:permissions)
    attrs[:active] = ActiveModel::Type::Boolean.new.cast(params[:active]) if params.key?(:active)

    @api_key.update!(attrs)
    redirect_to settings_api_keys_path
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: settings_api_keys_path,
      inertia: { errors: e.record.errors.to_hash }
  end

  def destroy
    @api_key.soft_delete!
    redirect_to settings_api_keys_path
  end

  private

  def set_api_key
    @api_key = current_workspace.api_keys.where(deleted_at: nil).find(params[:id])
  end
end
