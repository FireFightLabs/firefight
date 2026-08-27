class AbilityGrantsController < InertiaController
  authorizes Ability::Action::RESOURCE_PERMISSIONS, create: :create, update: :update, delete: :destroy

  def create
    principal = Ability::Principal.find!(current_workspace, params[:principal_kind], params[:principal_id])
    target = params[:role_id].present? ? { role: find_role! } : { action: find_action! }
    grant = Ability::Grant.grant!(
      workspace: current_workspace, principal: principal, target: target,
      environment_ids: params[:environment_ids], expires_at: params[:expires_at]
    )

    redirect_to gateway_permissions_path, notice: "#{principal.principal_label} was granted #{grant.label}#{expiry_suffix(grant)}."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to gateway_permissions_path, alert: e.record.errors.full_messages.to_sentence
  end

  def update
    grant = current_workspace.ability_grants.find(params[:id])
    grant.rescope!(
      environment_ids: params[:environment_ids],
      expires_at: params.key?(:expires_at) ? params[:expires_at] : :unchanged
    )

    redirect_to gateway_permissions_path, notice: "#{grant.label} was updated#{expiry_suffix(grant)}."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to gateway_permissions_path, alert: e.record.errors.full_messages.to_sentence
  end

  def destroy
    grant = current_workspace.ability_grants.find(params[:id])
    label = grant.label
    grant.destroy!
    redirect_to gateway_permissions_path, notice: "#{label} was revoked."
  end

  private

  def expiry_suffix(grant)
    return "" if grant.expires_at.blank?

    " until #{grant.expires_at.to_fs(:long)}"
  end

  def find_action!
    Ability::Action.grantable_for(current_workspace).find(params[:action_id])
  end

  def find_role!
    current_workspace.ability_roles.find(params[:role_id])
  end
end
