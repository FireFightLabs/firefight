module Ability
  # A workspace-defined bundle of actions, granted to principals as one
  # unit. Distinct from IncidentRole (incident staffing), this is the
  # permission-bundle side of the Ability Gateway.
  class Role < ApplicationRecord
    include Sluggable

    belongs_to :workspace

    has_many :role_actions, class_name: "Ability::RoleAction", inverse_of: :role, dependent: :destroy
    has_many :actions, through: :role_actions
    has_many :grants, class_name: "Ability::Grant", inverse_of: :role, dependent: :destroy

    validates :name, presence: true
    validates :slug, presence: true, uniqueness: { scope: :workspace_id },
                     format: { with: /\A[a-z0-9_]+\z/ }

      after_commit :bust_holder_caches

    # Replaces the set's contents in one write, so the caller states what the
    # set covers rather than diffing it. Scopes already pinned to a member
    # action survive, since they are the set's own overrides.
    def sync_actions!(action_ids)
      transaction do
        role_actions.where.not(action_id: action_ids).destroy_all
        (action_ids - role_actions.reload.map(&:action_id)).each do |action_id|
          role_actions.create!(action_id: action_id)
        end
      end
    end

    private

    def bust_holder_caches
      Ability::Resolver.bust_for_role!(self)
    end
  end
end
