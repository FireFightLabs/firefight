# The routing role gaps the workspace's alert rules would trip over: a rule
# targets a team, but no attribute on the Team type is tagged with the role
# the resolver needs. The alert routing page shows these as warnings and the
# MCP evaluate_routing tool returns them, the same gap the resolver notes at
# fire time.
class Alert::RoutingRoleGaps
  def self.for(workspace)
    new(workspace).sentences
  end

  def initialize(workspace)
    @workspace = workspace
  end

  def sentences
    return [] unless team_type

    sentences = []
    if pages_teams? && missing?(CatalogAttributeDefinition::ROLE_MEMBERS) && missing?(CatalogAttributeDefinition::ROLE_MANAGER)
      sentences << "Your #{team_type.name} type has no attribute marked as Members or Manager, so team targets cannot page anyone."
    end
    if notifies_teams? && missing?(CatalogAttributeDefinition::ROLE_NOTIFICATION_CHANNEL)
      sentences << "Your #{team_type.name} type has no attribute marked as Notification channel, so team notifications have nowhere to post."
    end
    sentences
  end

  private

  TEAM_TARGET_TYPES = [
    PolicyRule::AlertRoutingOutcome::TARGET_TEAM,
    PolicyRule::AlertRoutingOutcome::TARGET_OWNING_TEAM
  ].freeze

  def team_type
    @team_type ||= @workspace.catalog_types.active.find_by(system_key: CatalogType::SYSTEM_KEY_TEAM)
  end

  def missing?(role)
    team_type.role_attribute(role).nil?
  end

  def pages_teams?
    outcomes.any? do |outcome|
      Array(outcome["invite"]).any? { |target| TEAM_TARGET_TYPES.include?(target["type"]) }
    end
  end

  def notifies_teams?
    outcomes.any? do |outcome|
      TEAM_TARGET_TYPES.include?(outcome.dig("notify", "type"))
    end
  end

  def outcomes
    @outcomes ||= PolicyRule
      .joins(:policy)
      .where(policies: { workspace_id: @workspace.id, domain: Policy::DOMAIN_ALERT_ROUTING })
      .pluck(:outcome)
      .compact
  end
end
