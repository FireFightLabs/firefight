module Ability
  # Attaches an action (direct) or a role (bundle) to a principal. Scope
  # narrows where the grant applies (see Ability::Scope); ids in scopes,
  # labels only ever in the ledger.
  class Grant < ApplicationRecord
    belongs_to :workspace
    belongs_to :principal, polymorphic: true
    belongs_to :role, class_name: "Ability::Role", optional: true, inverse_of: :grants
    belongs_to :action, class_name: "Ability::Action", optional: true

    validates :action_id, uniqueness: { scope: [ :principal_type, :principal_id ] }, if: -> { action_id.present? }
    validates :role_id, uniqueness: { scope: [ :principal_type, :principal_id ] }, if: -> { role_id.present? }
    validate :exactly_one_target
    validate :scope_well_formed

    after_commit :bust_principal_cache

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

    private

    def exactly_one_target
      errors.add(:base, "grant must target exactly one of role or action") unless role_id.present? ^ action_id.present?
    end

    def scope_well_formed
      Ability::Scope.validate(scope, errors)
    end

    def bust_principal_cache
      Ability::Resolver.bust!(principal_type: principal_type, principal_id: principal_id)
    end
  end
end
