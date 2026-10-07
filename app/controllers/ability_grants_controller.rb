class AbilityGrantsController < InertiaController
  authorizes Ability::Action::RESOURCE_PERMISSIONS, create: %i[create withhold], update: :update, delete: :destroy

  def create
    principal = Ability::Principal.find!(current_workspace, params[:principal_kind], params[:principal_id])
    target = params[:role_id].present? ? { role: find_role! } : { action: find_action! }
    grant = Ability::Grant.grant!(
      workspace: current_workspace, principal: principal, target: target,
      environment_ids: params[:environment_ids], expires_at: params[:expires_at]
    )

    # Back to the page that asked, since the quick grant panel is not only on the Permissions screen.
    redirect_back fallback_location: gateway_permissions_path,
                  notice: "#{principal.actor_display_name} was granted #{grant.label}#{expiry_suffix(grant)}."
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: gateway_permissions_path, alert: e.record.errors.full_messages.to_sentence
  end

  # Takes a member's default away at once, one ability or a connection's reads. Revoking the grant this writes gives it back.
  def withhold
    principal = Ability::Principal.find!(current_workspace, params[:principal_kind], params[:principal_id])
    target = params[:role_id].present? ? { role: find_role! } : { action: find_action! }
    grant = Ability::Grant.withhold!(workspace: current_workspace, principal: principal, **target)

    redirect_to gateway_permissions_path,
                notice: "#{principal.actor_display_name} can no longer #{words_for(grant)}. Restore it to give it back."
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
    return redirect_to(gateway_permissions_path, notice: "#{grant.principal.actor_display_name} can #{words_for(grant)} again.") if grant.no_access?

    redirect_to gateway_permissions_path, notice: "#{label} was revoked."
  end

  private

  def expiry_suffix(grant)
    return "" if grant.expires_at.blank?

    " until #{grant.expires_at.to_fs(:long)}"
  end

  def words_for(grant)
    return grant.role.default_words if grant.role

    Ability::Action.described(grant.action.key)&.fetch(:title)&.downcase_first || grant.action.key
  end

  def find_action!
    Ability::Action.grantable_for(current_workspace).find(params[:action_id])
  end

  def find_role!
    current_workspace.ability_roles.find(params[:role_id])
  end
end
