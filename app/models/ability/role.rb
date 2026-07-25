module Ability
  # A workspace-defined bundle of actions, granted to principals as one
  # unit. Distinct from IncidentRole (incident staffing) — this is the
  # permission-bundle side of the Ability Gateway.
  class Role < ApplicationRecord
    belongs_to :workspace

    has_many :role_actions, class_name: "Ability::RoleAction", inverse_of: :role, dependent: :destroy
    has_many :actions, through: :role_actions
    has_many :grants, class_name: "Ability::Grant", inverse_of: :role, dependent: :destroy

    validates :name, presence: true
    validates :slug, presence: true, uniqueness: { scope: :workspace_id },
                     format: { with: /\A[a-z0-9_]+\z/ }

    after_commit :bust_holder_caches

    private

    def bust_holder_caches
      Ability::Resolver.bust_for_role!(self)
    end
  end
end
