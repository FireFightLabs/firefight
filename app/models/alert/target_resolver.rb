# Resolves outcome targets against the catalog at fire time, never stored,
# so routing follows catalog reorgs. Resolution is pure lookups and soft-fails:
# every miss is a note, never an exception. The incident must always win.
#
# owning_team: alert.service -> service entry -> owner-team reference -> team.
# A team's people come from the attributes tagged with the Members and
# Manager roles. Its channel comes from the Notification channel role, the
# service's own first (specific wins), then the team's. Roles, never slugs,
# so a workspace can name its attributes anything.
class Alert::TargetResolver
  def initialize(workspace, fields)
    @workspace = workspace
    @fields = fields
    @notes = []
  end

  attr_reader :notes

  # invite targets -> deduped WorkspaceMemberships
  def memberships_for(targets)
    Array(targets).flat_map { |target| target_memberships(target.with_indifferent_access) }.uniq
  end

  # notify target -> a postable conversation (channel id or member platform id)
  def channel_for(target)
    return nil if target.blank?

    target = target.with_indifferent_access
    case target[:type]
    when PolicyRule::AlertRoutingOutcome::TARGET_CHANNEL
      target[:channel_id]
    when PolicyRule::AlertRoutingOutcome::TARGET_MEMBER
      membership(target[:member_id])&.platform_user_id
    when PolicyRule::AlertRoutingOutcome::TARGET_TEAM
      team_channel(team_entry_by_id(target[:entry_id]))
    when PolicyRule::AlertRoutingOutcome::TARGET_OWNING_TEAM
      service_entry = service_entry_for(target[:of])
      channel = service_entry && service_entry.role_value(CatalogAttributeDefinition::ROLE_NOTIFICATION_CHANNEL).presence
      channel || team_channel(owning_team(target[:of]))
    end
  end

  private

  def target_memberships(target)
    case target[:type]
    when PolicyRule::AlertRoutingOutcome::TARGET_MEMBER
      Array(membership(target[:member_id]))
    when PolicyRule::AlertRoutingOutcome::TARGET_TEAM
      team_members(team_entry_by_id(target[:entry_id]))
    when PolicyRule::AlertRoutingOutcome::TARGET_OWNING_TEAM
      team_members(owning_team(target[:of]))
    else
      []
    end
  end

  def membership(id)
    found = @workspace.workspace_memberships.find_by(id: id)
    note("member #{id} not found in workspace") unless found
    found
  end

  def team_members(team)
    return [] unless team

    members_attribute = team.catalog_type.role_attribute(CatalogAttributeDefinition::ROLE_MEMBERS)
    manager_attribute = team.catalog_type.role_attribute(CatalogAttributeDefinition::ROLE_MANAGER)
    if members_attribute.nil? && manager_attribute.nil?
      note("the #{team.catalog_type.name} type has no attribute marked as Members or Manager")
      return []
    end

    ids = (Array(members_attribute && team.entry_attributes[members_attribute.slug]) +
           [ manager_attribute && team.entry_attributes[manager_attribute.slug] ]).compact.uniq
    if ids.empty?
      note("team #{team.slug} has no members or manager set")
      return []
    end

    found = @workspace.workspace_memberships.where(id: ids).to_a
    note("team #{team.slug}: #{ids.size - found.size} member reference(s) no longer exist") if found.size < ids.size
    found
  end

  def team_channel(team)
    return nil unless team

    channel_attribute = team.catalog_type.role_attribute(CatalogAttributeDefinition::ROLE_NOTIFICATION_CHANNEL)
    unless channel_attribute
      note("the #{team.catalog_type.name} type has no attribute marked as Notification channel")
      return nil
    end

    channel = team.entry_attributes[channel_attribute.slug].presence
    note("team #{team.slug} has no notification channel set") unless channel
    channel
  end

  def owning_team(field)
    service = service_entry_for(field)
    return nil unless service

    relationship = service.active_outgoing_relationships.detect do |candidate|
      candidate.target_entry.catalog_type.system_key == CatalogType::SYSTEM_KEY_TEAM
    end
    unless relationship
      note("service #{service.slug} has no owning team in the catalog")
      return nil
    end

    relationship.target_entry
  end

  def service_entry_for(field)
    slug = @fields[field.to_s].presence
    unless slug
      note("alert has no #{field} field to resolve an owning team from")
      return nil
    end

    @service_entries ||= {}
    return @service_entries[slug] if @service_entries.key?(slug)

    entry = @workspace.catalog_entries.in_system_type(field.to_s).find_by(slug: slug)
    note("#{field} #{slug.inspect} is not in the catalog") unless entry
    @service_entries[slug] = entry
  end

  def team_entry_by_id(id)
    entry = @workspace.catalog_entries.active.find_by(id: id)
    note("catalog team #{id} not found") unless entry
    entry
  end

  def note(message)
    @notes << message
  end
end
