module Ability
  # Cached per principal and busted on any grant or role write, so a revoke
  # takes effect on the next call. The TTL is only a safety net.
  class Resolver
    CACHE_PREFIX = "ability/resolved/v3/"
    CACHE_TTL = 1.hour

    # by_key holds live grants only. ever_granted also names the keys of expired ones, since a grant that narrows a
    # default keeps narrowing once it lapses rather than handing the default back.
    ResolvedGrants = Data.define(:by_key, :ever_granted) do
      def covers?(action_key, requested_scope = {})
        scopes = by_key[action_key]
        return false unless scopes

        scopes.any? { |scope| Ability::Scope.covers?(scope, requested_scope) }
      end

      def action_keys
        by_key.keys
      end

      def granted_ever?(action_key) = ever_granted.include?(action_key)

      # Where the live grants for action_key reach, as a scope: {} for every environment, the environments they name, or
      # nil when none is live. A grant that names no environment reaches every one.
      def reach(action_key)
        scopes = by_key[action_key]
        return nil if scopes.blank?

        environments = scopes.map { |scope| scope[Ability::Scope::DIMENSION_ENVIRONMENT] || scope[Ability::Scope::DIMENSION_ENVIRONMENT.to_sym] }
        return {} if environments.any?(&:nil?)

        { Ability::Scope::DIMENSION_ENVIRONMENT => environments.flatten.uniq }
      end
    end

    # Workspace is required rather than read off the principal, because a principal
    # can be global and hold different grants in each workspace.
    # Written rather than fetched because the TTL depends on the result. A
    # grant expiring in ten minutes must not sit in an hour-long cache.
    def self.resolve(principal, workspace)
      workspace_id = workspace.is_a?(Workspace) ? workspace.id : workspace
      key = cache_key(principal.class.polymorphic_name, principal.id, workspace_id)
      resolved = Rails.cache.read(key)

      if resolved.nil?
        resolved = { by_key: compute(principal, workspace_id), ever_granted: ever_granted(principal, workspace_id) }
        Rails.cache.write(key, resolved, expires_in: cache_ttl_for(principal, workspace_id))
      end

      ResolvedGrants.new(by_key: resolved[:by_key], ever_granted: resolved[:ever_granted])
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

    # A connection's read pack also holds the reads through its tools that can change things too (Role.reads_key).
    def self.compute(principal, workspace_id)
      by_key = {}
      grants = Grant.where(principal: principal, workspace_id: workspace_id)
                    .live.includes(:action, role: { role_actions: :action })

      withheld = []
      grants.each do |grant|
        if grant.no_access?
          withheld.concat(grant.action ? [ grant.action.key ] : grant.role.role_actions.map { |role_action| role_action.action.key })
          withheld << Role.reads_key(grant.role.integration_id) if grant.role&.read_pack?
        elsif grant.action
          (by_key[grant.action.key] ||= []) << grant.scope
        else
          grant.role.role_actions.each do |role_action|
            (by_key[role_action.action.key] ||= []) << (grant.scope.presence || role_action.default_scope)
          end
          (by_key[Role.reads_key(grant.role.integration_id)] ||= []) << grant.scope if grant.role.read_pack?
        end
      end

      # No access outranks any set that would otherwise reach the same ability.
      by_key.except(*withheld)
    end

    # Every key a grant names, live or expired, directly or through a set.
    def self.ever_granted(principal, workspace_id)
      grants = Grant.where(principal: principal, workspace_id: workspace_id)
      direct = Action.where(id: grants.select(:action_id)).pluck(:key)
      through_sets = Action.joins(:role_actions).where(ability_role_actions: { role_id: grants.select(:role_id) }).pluck(:key)
      read_packs = grants.joins(:role).where(ability_roles: { pack: Role::PACK_READ }).pluck("ability_roles.integration_id").map { |id| Role.reads_key(id) }
      (direct + through_sets + read_packs).uniq
    end

    def self.cache_key(principal_type, principal_id, workspace_id)
      "#{CACHE_PREFIX}#{principal_type}/#{principal_id}/#{workspace_id}"
    end
  end
end
