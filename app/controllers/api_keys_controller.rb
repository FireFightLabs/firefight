class ApiKeysController < InertiaController
  KIND_PERSONAL = "personal"

  before_action :set_api_key, only: [ :update, :destroy, :abilities ]

  # Personal tokens are self-service (any member can mint their own, GitHub
  # PAT style). Service keys carry workspace-wide scopes and are the
  # gateway's api_keys resource.
  def create
    personal = params[:kind] == KIND_PERSONAL
    return unless personal || authorize_web!(Ability::Action::RESOURCE_API_KEYS, Ability::Action::ACTION_CREATE)

    api_key, raw_token = ActiveRecord::Base.transaction do
      key, token = ApiKey.create_with_token!(
        workspace: current_workspace,
        created_by: current_membership,
        on_behalf_of: personal ? current_membership : nil,
        name: params.require(:name),
        expires_at: params[:expires_at].present? ? Time.zone.parse(params[:expires_at]) : nil
      )
      # A personal token acts as its human and holds no grants of its own.
      key.replace_permissions!(params[:permissions]&.to_unsafe_h || {}) unless personal
      [ key, token ]
    end

    flash.inertia[:api_key_token] = raw_token
    redirect_to developer_api_keys_path
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: developer_api_keys_path,
      inertia: { errors: e.record.errors.to_hash }
  rescue ArgumentError => e
    redirect_back fallback_location: developer_api_keys_path, alert: e.message
  end

  # Only touch fields the client explicitly passes. Omitting `active` would
  # otherwise write nil into a NOT NULL column, and permissions are grants now,
  # so they are replaced separately rather than assigned as an attribute.
  def update
    attrs = {}
    attrs[:name] = params[:name] if params.key?(:name)
    attrs[:active] = ActiveModel::Type::Boolean.new.cast(params[:active]) if params.key?(:active)

    ActiveRecord::Base.transaction do
      @api_key.update!(attrs)
      @api_key.replace_permissions!(params[:permissions].to_unsafe_h) if params.key?(:permissions)
    end

    redirect_to developer_api_keys_path
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: developer_api_keys_path,
      inertia: { errors: e.record.errors.to_hash }
  rescue ArgumentError => e
    redirect_back fallback_location: developer_api_keys_path, alert: e.message
  end

  def destroy
    @api_key.soft_delete!
    redirect_to developer_api_keys_path
  end

  # The grant preview, what this key can actually do, as resolved by the
  # gateway, the debugging answer to "why was this call denied?"
  def abilities
    if @api_key.personal?
      render json: { principal: @api_key.principal.principal_label, mode: KIND_PERSONAL,
                     abilities: Ability::Preview.implicit_member_reads }
    else
      render json: { principal: @api_key.principal_label, mode: "service",
                     abilities: Ability::Preview.for(@api_key) }
    end
  end

  private

  SERVICE_KEY_ACTIONS = {
    "update" => Ability::Action::ACTION_UPDATE,
    "destroy" => Ability::Action::ACTION_DELETE,
    "abilities" => Ability::Action::ACTION_READ
  }.freeze

  # A member reaches only their own personal tokens. Anything done to a
  # service key is authorized as the api_keys resource.
  def set_api_key
    scope = current_workspace.api_keys.where(deleted_at: nil)
    scope = scope.where(workspace_membership_id: current_membership.id) unless current_membership.admin_access?
    @api_key = scope.find(params[:id])
    authorize_web!(Ability::Action::RESOURCE_API_KEYS, SERVICE_KEY_ACTIONS.fetch(action_name)) unless @api_key.personal?
  end
end
