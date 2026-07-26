class AbilityGrantsController < InertiaController
  before_action :require_authentication
  before_action :require_admin!

  # A grant targets exactly one of a set or a single action, which the DB
  # enforces; which one arrived decides how the row is looked up.
  def create
    principal = find_principal!
    target = params[:role_id].present? ? { role: find_role! } : { action: find_action! }

    grant = current_workspace.ability_grants.find_or_initialize_by({ principal: principal }.merge(target))
    grant.scope = requested_scope
    grant.save!

    redirect_to settings_permissions_path
  rescue ActiveRecord::RecordInvalid => e
    redirect_to settings_permissions_path, alert: e.record.errors.full_messages.to_sentence
  end

  def update
    grant = current_workspace.ability_grants.find(params[:id])
    grant.update!(scope: requested_scope)

    redirect_to settings_permissions_path
  rescue ActiveRecord::RecordInvalid => e
    redirect_to settings_permissions_path, alert: e.record.errors.full_messages.to_sentence
  end

  def destroy
    current_workspace.ability_grants.find(params[:id]).destroy!
    redirect_to settings_permissions_path
  end

  private

  # An empty environment list means unrestricted, which Ability::Scope spells
  # as the dimension being absent rather than an empty array.
  def requested_scope
    requested = Array(params[:environment_ids]).map(&:to_s).select(&:present?)
    ids = current_workspace.environment_entries.where(id: requested).pluck(:id)
    ids.any? ? { Ability::Scope::DIMENSION_ENVIRONMENT => ids } : {}
  end

  # Grants attach to principals of this workspace only; the polymorphic type
  # arrives from the client, so it is matched against a fixed allowlist
  # rather than constantized.
  def find_principal!
    case params[:principal_type]
    when WorkspaceMembership.polymorphic_name then current_workspace.workspace_memberships.find(params[:principal_id])
    when Agent.polymorphic_name then current_workspace.agents.find(params[:principal_id])
    when ApiKey.polymorphic_name then current_workspace.api_keys.service.find(params[:principal_id])
    else raise ActiveRecord::RecordNotFound
    end
  end

  def find_action!
    Ability::Action.where(workspace_id: [ nil, current_workspace.id ]).find(params[:action_id])
  end

  def find_role!
    current_workspace.ability_roles.find(params[:role_id])
  end
end
