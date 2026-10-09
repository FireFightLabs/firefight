module Ability
  # A permission bundle, not to be confused with IncidentRole.
  class Role < ApplicationRecord
    include Sluggable
    include Packs

    belongs_to :workspace

    has_many :role_actions, class_name: "Ability::RoleAction", inverse_of: :role, dependent: :destroy
    has_many :actions, through: :role_actions
    has_many :grants, class_name: "Ability::Grant", inverse_of: :role, dependent: :destroy

    validates :name, presence: true
    validates :slug, presence: true, uniqueness: { scope: :workspace_id },
                     format: { with: /\A[a-z0-9_]+\z/ }

    after_commit :bust_holder_caches

    # Who holds each set, counted in one query for the whole list so deleting can say what is lost. A No access grant
    # takes a default away rather than holding it, so it is not counted.
    scope :with_holder_counts, -> {
      select(
        "#{table_name}.*",
        *holder_kinds.map do |column, holders|
          types = holders.map { |holder| connection.quote(holder.name) }.join(", ")
          "(SELECT COUNT(*) FROM ability_grants WHERE ability_grants.role_id = #{table_name}.id " \
            "AND ability_grants.principal_type IN (#{types}) " \
            "AND (ability_grants.scope ->> #{connection.quote(Ability::Scope::NO_ACCESS_KEY)}) IS DISTINCT FROM 'true') AS #{column}"
        end
      )
    }

    def self.holder_kinds = { people_count: [ WorkspaceMembership ], key_count: [ ApiKey ], agent_count: [ Agent, SystemAgent ] }

    # Scopes already pinned to a member action survive, they are the set's own overrides. A built-in pack is kept in
    # step by Firefight, so it refuses a hand edit.
    def sync_actions!(action_ids)
      blocked = edit_blocked_reason
      raise ActiveRecord::RecordInvalid.new(tap { errors.add(:base, blocked) }) if blocked

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
