class PrincipalSerializer < BaseSerializer
  object_as :principal

  type :string
  def id
    principal.id
  end

  # Grants are polymorphic, so the type travels with the id and the two
  # together address a principal on the way back in.
  type :string
  def principal_type
    principal.class.polymorphic_name
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

  # Set grants and single-action grants share a row shape so the UI lists
  # them together: what it covers is a label plus a count, not a kind check.
  type "{ id: string; kind: string; targetId: string; label: string; riskLevel: string | null; " \
       "actionCount: number; environmentIds: string[] }[]"
  def grants
    principal.ability_grants.filter_map do |grant|
      environment_ids = Array(grant.scope[Ability::Scope::DIMENSION_ENVIRONMENT])

      if grant.action
        { id: grant.id, kind: "action", targetId: grant.action_id, label: grant.action.key,
          riskLevel: grant.action.risk_level, actionCount: 1, environmentIds: environment_ids }
      elsif grant.role
        { id: grant.id, kind: "set", targetId: grant.role_id, label: grant.role.name,
          riskLevel: nil, actionCount: grant.role.role_actions.size, environmentIds: environment_ids }
      end
    end.sort_by { |grant| [ grant[:kind], grant[:label] ] }
  end
end
