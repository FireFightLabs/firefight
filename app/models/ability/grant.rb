module Ability
  # Attaches an action (direct) or a role (bundle) to a principal. Scope
  # narrows where the grant applies (see Ability::Scope). ids in scopes,
  # labels only ever in the ledger.
  class Grant < ApplicationRecord
    belongs_to :workspace
    belongs_to :principal, polymorphic: true
    belongs_to :role, class_name: "Ability::Role", optional: true, inverse_of: :grants
    belongs_to :action, class_name: "Ability::Action", optional: true

    validates :action_id, uniqueness: { scope: [ :principal_type, :principal_id ] }, if: -> { action_id.present? }
    validates :role_id, uniqueness: { scope: [ :principal_type, :principal_id ] }, if: -> { role_id.present? }
    validate :exactly_one_target
    validate :action_grantable
    validate :scope_well_formed
    validate :expiry_in_the_future, if: -> { expires_at_changed? && expires_at.present? }

    # An expired grant is kept rather than deleted, so the screen can say the
    # access lapsed instead of leaving someone wondering who removed it.
    scope :live, -> { where(expires_at: nil).or(where(expires_at: Time.current..)) }

    after_commit :bust_principal_cache

    # What an admin can hand out here, every global system action plus the
    # tool actions this workspace has minted by enabling a capability.
    def self.grantable_actions(workspace)
      Ability::Action.grantable_for(workspace).includes(source: :integration).order(:kind, :key)
    end

    # What the API and MCP hand out: a permission set by slug, or an ability
    # by key. Naming neither is a missing parameter, not a lookup miss.
    def self.target_for!(workspace, ability: nil, permission_set: nil)
      return { role: workspace.ability_roles.find_by!(slug: permission_set.to_s) } if permission_set.present?
      raise ActionController::ParameterMissing, :ability if ability.blank?

      { action: Ability::Action.grantable_for(workspace).find_by!(key: ability.to_s) }
    end

    # One grant per principal per target is a DB invariant, so granting
    # again retargets the existing row instead of duplicating it. `target`
    # is `{ action: }` or `{ role: }`.
    def self.grant!(workspace:, principal:, target:, environment_ids: [], expires_at: nil)
      grant = workspace.ability_grants.find_or_initialize_by({ principal: principal }.merge(target))
      grant.scope = Ability::Scope.for_environments(workspace, environment_ids)
      grant.expires_at = parse_expiry(grant, expires_at)
      grant.save!
      grant
    end

    # A blank value clears the expiry. An unreadable one is a validation
    # error rather than a silent nil.
    def self.parse_expiry(grant, value)
      return nil if value.blank?
      return value if value.respond_to?(:to_time) && !value.is_a?(String)

      Time.zone.parse(value.to_s) or
        raise ActiveRecord::RecordInvalid.new(grant.tap { |record| record.errors.add(:expires_at, "is not a valid date") })
    end

    # Reconciles a principal's direct grants over a bounded set of action
    # keys: grants inside `managed_keys` but absent from `desired_keys` are
    # removed, missing ones created. Grants outside `managed_keys` (e.g.
    # tool actions) are never touched.
    def self.sync_direct!(principal:, workspace:, desired_keys:, managed_keys:)
      transaction do
        existing = where(principal: principal)
                     .joins(:action)
                     .where(ability_actions: { key: managed_keys })
                     .index_by { |grant| grant.action.key }

        (existing.keys - desired_keys).each { |key| existing[key].destroy! }

        (desired_keys - existing.keys).each do |key|
          create!(workspace: workspace, principal: principal, action: Ability::Action.system!(key))
        end
      end
    end

    def expired?
      expires_at.present? && expires_at <= Time.current
    end

    def label
      action&.key || role&.name
    end

    def environment_ids
      Array(scope[Ability::Scope::DIMENSION_ENVIRONMENT])
    end

    # Changing the environments and changing the expiry are separate
    # controls, so an absent expiry means "leave it alone".
    def rescope!(environment_ids:, expires_at: :unchanged)
      attrs = { scope: Ability::Scope.for_environments(workspace, environment_ids) }
      attrs[:expires_at] = self.class.parse_expiry(self, expires_at) unless expires_at == :unchanged
      update!(attrs)
    end

    private

    def expiry_in_the_future
      errors.add(:expires_at, "must be in the future") if expires_at <= Time.current
    end

    def exactly_one_target
      errors.add(:base, "grant must target exactly one of role or action") unless role_id.present? ^ action_id.present?
    end

    def scope_well_formed
      Ability::Scope.validate(scope, errors)
    end

    def action_grantable
      errors.add(:action, "is admin-only and cannot be granted") if action&.admin_only?
    end

    def bust_principal_cache
      Ability::Resolver.bust!(principal_type: principal_type, principal_id: principal_id)
    end
  end
end
