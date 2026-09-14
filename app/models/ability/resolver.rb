module Ability
  # Cached per principal and busted on any grant or role write, so a revoke
  # takes effect on the next call. The TTL is only a safety net.
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

    # Workspace is required rather than read off the principal, because a principal
    # can be global and hold different grants in each workspace.
    # Written rather than fetched because the TTL depends on the result. A
    # grant expiring in ten minutes must not sit in an hour-long cache.
    def self.resolve(principal, workspace)
      workspace_id = workspace.is_a?(Workspace) ? workspace.id : workspace
      key = cache_key(principal.class.polymorphic_name, principal.id, workspace_id)
      by_key = Rails.cache.read(key)

      if by_key.nil?
        by_key = compute(principal, workspace_id)
        Rails.cache.write(key, by_key, expires_in: cache_ttl_for(principal, workspace_id))
      end

      ResolvedGrants.new(by_key: by_key)
    end

    def self.cache_ttl_for(principal, workspace_id)
      next_expiry = Grant.where(principal: principal, workspace_id: workspace_id).live.minimum(:expires_at)
      return CACHE_TTL if next_expiry.nil?

      [ next_expiry - Time.current, CACHE_TTL ].min.clamp(1.second, CACHE_TTL)
    end

    def self.bust!(principal_type:, principal_id:, workspace_id:)
      Rails.cache.delete(cache_key(principal_type, principal_id, workspace_id))
    end

    def self.bust_for_role!(role)
      Grant.where(role_id: role.id).pluck(:principal_type, :principal_id, :workspace_id).each do |type, id, workspace_id|
        bust!(principal_type: type, principal_id: id, workspace_id: workspace_id)
      end
    end

    def self.compute(principal, workspace_id)
      by_key = {}
      grants = Grant.where(principal: principal, workspace_id: workspace_id)
                    .live.includes(:action, role: { role_actions: :action })

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

    def self.cache_key(principal_type, principal_id, workspace_id)
      "#{CACHE_PREFIX}#{principal_type}/#{principal_id}/#{workspace_id}"
    end
  end
end
