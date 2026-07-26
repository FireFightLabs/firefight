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

  type "{ id: string; actionId: string; actionKey: string; riskLevel: string; environmentIds: string[] }[]"
  def grants
    principal.ability_grants.select(&:action).map do |grant|
      { id: grant.id, actionId: grant.action_id, actionKey: grant.action.key,
        riskLevel: grant.action.risk_level,
        environmentIds: Array(grant.scope[Ability::Scope::DIMENSION_ENVIRONMENT]) }
    end.sort_by { |grant| grant[:actionKey] }
  end
end
