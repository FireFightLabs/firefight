class PrincipalSerializer < BaseSerializer
  object_as :principal

  type :string
  def id
    principal.id
  end

  type :string
  def name
    principal.actor_display_name
  end

  type :string
  def kind
    principal.actor_kind
  end

  type :string
  def implicit_authority
    principal.implicit_authority.to_s
  end

  # Set grants and single-action grants share a row shape. What it covers is a label plus a count.
  type "{ id: string; kind: string; targetId: string; label: string; title: string | null; description: string | null; " \
       "riskLevel: string | null; actionCount: number; environmentIds: string[]; expiresAt: string | null; expired: boolean }[]"
  def grants
    principal.ability_grants.filter_map do |grant|
      environment_ids = Array(grant.scope[Ability::Scope::DIMENSION_ENVIRONMENT])
      timing = { expiresAt: grant.expires_at&.utc&.iso8601, expired: grant.expired? }

      if grant.action
        described = Ability::Action.described(grant.action.key)
        { id: grant.id, kind: "action", targetId: grant.action_id, label: grant.action.key, title: described&.fetch(:title),
          description: described&.fetch(:description), riskLevel: grant.action.risk_level, actionCount: 1, environmentIds: environment_ids, **timing }
      elsif grant.role
        { id: grant.id, kind: "set", targetId: grant.role_id, label: grant.role.name, title: nil, description: nil,
          riskLevel: nil, actionCount: grant.role.role_actions.size, environmentIds: environment_ids, **timing }
      end
    end.sort_by { |grant| [ grant[:kind], grant[:label] ] }
  end
end
