class AbilityGrantsController < InertiaController
  before_action :require_authentication
  before_action :require_admin!

  # A grant targets exactly one of a set or a single action, which the DB
  # enforces. Which one arrived decides how the row is looked up.
  def create
    principal = find_principal!
    target = params[:role_id].present? ? { role: find_role! } : { action: find_action! }

    grant = current_workspace.ability_grants.find_or_initialize_by({ principal: principal }.merge(target))
    grant.scope = requested_scope
    grant.expires_at = requested_expiry
    grant.save!

    redirect_to settings_permissions_path, notice: "#{principal.principal_label} was granted #{grant_label(grant)}#{expiry_suffix(grant)}."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to settings_permissions_path, alert: e.record.errors.full_messages.to_sentence
  end

  # Changing the environment scope and changing the expiry are separate
  # controls, so an absent expires_at means "leave it alone" rather than
  # "clear it". Clearing is an explicit empty string.
  def update
    grant = current_workspace.ability_grants.find(params[:id])
    attrs = { scope: requested_scope }
    attrs[:expires_at] = requested_expiry if params.key?(:expires_at)
    grant.update!(attrs)

    redirect_to settings_permissions_path, notice: "#{grant_label(grant)} was updated#{expiry_suffix(grant)}."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to settings_permissions_path, alert: e.record.errors.full_messages.to_sentence
  end

  def destroy
    grant = current_workspace.ability_grants.find(params[:id])
    label = grant_label(grant)
    grant.destroy!
    redirect_to settings_permissions_path, notice: "#{label} was revoked."
  end

  private

  # Absent or blank means the grant does not expire, which is how an admin
  # clears an expiry they set earlier.
  def requested_expiry
    return nil if params[:expires_at].blank?

    Time.zone.parse(params[:expires_at].to_s) or
      raise ActiveRecord::RecordInvalid.new(Ability::Grant.new.tap { |g| g.errors.add(:expires_at, "is not a valid date") })
  end

  def grant_label(grant)
    grant.action&.key || grant.role&.name
  end

  def expiry_suffix(grant)
    return "" if grant.expires_at.blank?

    " until #{grant.expires_at.to_fs(:long)}"
  end

  # An empty environment list means unrestricted, which Ability::Scope spells
  # as the dimension being absent rather than an empty array.
  def requested_scope
    requested = Array(params[:environment_ids]).map(&:to_s).select(&:present?)
    ids = current_workspace.environment_entries.where(id: requested).pluck(:id)
    ids.any? ? { Ability::Scope::DIMENSION_ENVIRONMENT => ids } : {}
  end

  # Grants attach to principals of this workspace only. The polymorphic type
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
