module Ability
  # Resolves a principal to its effective grant set: the union of direct
  # action grants and role-bundle actions, each carrying its scope. Cached
  # per principal; busted immediately on any grant/role write so a revoke
  # takes effect on the next call — the TTL is only a safety net.
  class Resolver
    CACHE_PREFIX = "ability/resolved/v1/"
    CACHE_TTL = 1.hour

    ResolvedGrants = Data.define(:by_key) do
      def covers?(action_key, requested_scope = {})
        scopes = by_key[action_key]
        return false unless scopes

        scopes.any? { |scope| Ability::Scope.covers?(scope, requested_scope) }
      end

      def action_keys
        by_key.keys
      end
    end

    def self.resolve(principal)
      by_key = Rails.cache.fetch(cache_key(principal.class.polymorphic_name, principal.id), expires_in: CACHE_TTL) do
        compute(principal)
      end
      ResolvedGrants.new(by_key: by_key)
    end

    def self.bust!(principal_type:, principal_id:)
      Rails.cache.delete(cache_key(principal_type, principal_id))
    end

    def self.bust_for_role!(role)
      Grant.where(role_id: role.id).pluck(:principal_type, :principal_id).each do |type, id|
        bust!(principal_type: type, principal_id: id)
      end
    end

    def self.compute(principal)
      by_key = {}
      grants = Grant.where(principal: principal).includes(:action, role: { role_actions: :action })

      grants.each do |grant|
        if grant.action
          (by_key[grant.action.key] ||= []) << grant.scope
        else
          grant.role.role_actions.each do |role_action|
            (by_key[role_action.action.key] ||= []) << (grant.scope.presence || role_action.default_scope)
          end
        end
      end

      by_key
    end

    def self.cache_key(principal_type, principal_id)
      "#{CACHE_PREFIX}#{principal_type}/#{principal_id}"
    end
  end
end
