class ApiKeysController < InertiaController
  KIND_PERSONAL = "personal"

  before_action :require_authentication
  before_action :set_api_key, only: [ :update, :destroy ]

  # Personal tokens are self-service (any member can mint their own, GitHub
  # PAT style); service keys carry workspace-wide scopes and need an admin.
  def create
    personal = params[:kind] == KIND_PERSONAL
    return require_admin! unless personal || current_membership.admin_access?

    api_key, raw_token = ApiKey.create_with_token!(
      workspace: current_workspace,
      created_by: current_membership,
      on_behalf_of: personal ? current_membership : nil,
      name: params.require(:name),
      permissions: personal ? {} : params[:permissions]&.to_unsafe_h || {},
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

  # Admins manage every key; members only their own personal tokens.
  def set_api_key
    scope = current_workspace.api_keys.where(deleted_at: nil)
    scope = scope.where(workspace_membership_id: current_membership.id) unless current_membership.admin_access?
    @api_key = scope.find(params[:id])
  end
end
