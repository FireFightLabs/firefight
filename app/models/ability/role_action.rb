module Ability
  class RoleAction < ApplicationRecord
    belongs_to :role, class_name: "Ability::Role", inverse_of: :role_actions
    belongs_to :action, class_name: "Ability::Action"

    validates :action_id, uniqueness: { scope: :role_id }
    validate :default_scope_well_formed
    validate :action_grantable

    after_commit :bust_holder_caches

    private

    def default_scope_well_formed
      Ability::Scope.validate(default_scope, errors, attribute: :default_scope)
    end

    def action_grantable
      errors.add(:action, "is admin-only and cannot be part of a set") if action&.admin_only?
    end

    def bust_holder_caches
      Ability::Resolver.bust_for_role!(role)
    end
  end
end
