module Ability
  # Scopes hold ids, labels only ever go in the ledger.
  class Grant < ApplicationRecord
    belongs_to :workspace
    belongs_to :principal, polymorphic: true
    belongs_to :role, class_name: "Ability::Role", optional: true, inverse_of: :grants
    belongs_to :action, class_name: "Ability::Action", optional: true

    # Workspace is part of the key so a global principal can hold different grants per tenant.
    validates :action_id, uniqueness: { scope: [ :principal_type, :principal_id, :workspace_id ] },
                          if: -> { action_id.present? }
    validates :role_id, uniqueness: { scope: [ :principal_type, :principal_id, :workspace_id ] },
                        if: -> { role_id.present? }
    validate :exactly_one_target
    validate :action_grantable
    validate :scope_well_formed
    validate :expiry_in_the_future, if: -> { expires_at_changed? && expires_at.present? }
    validate :no_access_only_for_a_member_default, if: :no_access?

    NO_ACCESS_ONLY_FOR_DEFAULTS = "No access applies only to what members hold without a grant.".freeze
    NO_ACCESS_NOT_FOR_ADMINS = "Admins hold every ability, so they cannot be given no access.".freeze
    NO_ACCESS_HAS_NO_REACH = "No access has no environments or expiry. Restore the default first, then grant it.".freeze

    # Expired grants are kept so the screen can say the access lapsed.
    scope :live, -> { where(expires_at: nil).or(where(expires_at: Time.current..)) }

    after_commit :bust_principal_cache

    def self.grantable_actions(workspace)
      Ability::Action.grantable_for(workspace).includes(source: :integration).order(:kind, :key)
    end

    # Naming neither is a missing parameter, not a lookup miss.
    def self.target_for!(workspace, ability: nil, permission_set: nil)
      return { role: workspace.ability_roles.find_by!(slug: permission_set.to_s) } if permission_set.present?
      raise ActionController::ParameterMissing, :ability if ability.blank?

      { action: Ability::Action.grantable_for(workspace).find_by!(key: ability.to_s) }
    end

    # One grant per principal per target is a DB invariant, so granting again
    # retargets the existing row.
    def self.grant!(workspace:, principal:, target:, environment_ids: [], expires_at: nil)
      grant = workspace.ability_grants.find_or_initialize_by({ principal: principal }.merge(target))
      grant.scope = Ability::Scope.for_environments(workspace, environment_ids)
      grant.expires_at = parse_expiry(grant, expires_at)
      grant.save!
      grant
    end

    # Takes a member's default away at once, replacing any grant of the same ability or read pack. Revoking it gives the
    # default back.
    def self.withhold!(workspace:, principal:, action: nil, role: nil)
      grant = workspace.ability_grants.find_or_initialize_by({ principal: principal }.merge(role ? { role: role } : { action: action }))
      grant.update!(scope: Ability::Scope::NO_ACCESS, expires_at: nil)
      grant
    end

    # Blank clears the expiry, unreadable is a validation error rather than a silent nil.
    def self.parse_expiry(grant, value)
      return nil if value.blank?
      return value if value.respond_to?(:to_time) && !value.is_a?(String)

      Time.zone.parse(value.to_s) or
        raise ActiveRecord::RecordInvalid.new(grant.tap { |record| record.errors.add(:expires_at, "is not a valid date") })
    end

    def self.replace_system_grants!(principal:, workspace:, matrix:)
      desired = Array(matrix).flat_map do |resource, actions|
        Array(actions).map { |action| Ability::Action.system_key(resource, action) }
      end
      unknown = desired - Ability::Action.grantable_keys
      raise ArgumentError, "unknown permission #{unknown.first}" if unknown.any?

      sync_direct!(
        principal: principal, workspace: workspace,
        desired_keys: desired, managed_keys: Ability::Action.grantable_keys
      )
    end

    # Grants outside managed_keys, such as tool actions, are never touched.
    def self.sync_direct!(principal:, workspace:, desired_keys:, managed_keys:)
      transaction do
        existing = where(principal: principal, workspace_id: workspace.id)
                     .joins(:action)
                     .where(ability_actions: { key: managed_keys })
                     .index_by { |grant| grant.action.key }

        (existing.keys - desired_keys).each { |key| existing[key].destroy! }

        (desired_keys - existing.keys).each do |key|
          create!(workspace: workspace, principal: principal, action: Ability::Action.system!(key))
        end
      end
    end

    def no_access? = Ability::Scope.no_access?(scope)

    def expired?
      expires_at.present? && expires_at <= Time.current
    end

    def label
      action&.key || role&.name
    end

    def environment_ids
      Array(scope[Ability::Scope::DIMENSION_ENVIRONMENT])
    end

    # Environments and expiry are separate controls, so an absent expiry means leave it alone.
    def rescope!(environment_ids:, expires_at: :unchanged)
      raise ActiveRecord::RecordInvalid.new(tap { errors.add(:base, NO_ACCESS_HAS_NO_REACH) }) if no_access?

      attrs = { scope: Ability::Scope.for_environments(workspace, environment_ids) }
      attrs[:expires_at] = self.class.parse_expiry(self, expires_at) unless expires_at == :unchanged
      update!(attrs)
    end

    private

    def expiry_in_the_future
      errors.add(:expires_at, "must be in the future") if expires_at <= Time.current
    end

    def no_access_only_for_a_member_default
      return errors.add(:base, NO_ACCESS_ONLY_FOR_DEFAULTS) unless principal.is_a?(WorkspaceMembership) &&
                                                                   WorkspaceMembership.default_target?(action: action, role: role)

      errors.add(:base, NO_ACCESS_NOT_FOR_ADMINS) if principal.admin_access?
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
      Ability::Resolver.bust!(
        principal_type: principal_type, principal_id: principal_id, workspace_id: workspace_id
      )
    end
  end
end
