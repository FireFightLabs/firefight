# Resolves outcome targets against the catalog at fire time, never stored,
# so routing follows catalog reorgs. Resolution is pure lookups and soft-fails:
# every miss is a note, never an exception; the incident must always win.
#
# owning_team: alert.service -> service entry -> owner-team reference -> team.
# A team's people are its `members` + `manager` attributes; its channel is the
# service's own `slack_channel` first (specific wins), then the team's.
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
      channel = service_entry && service_entry[:attributes]["slack_channel"].presence
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

    attrs = team[:attributes]
    ids = (Array(attrs["members"]) + [ attrs["manager"] ]).compact.uniq
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

    channel = team[:attributes]["slack_channel"].presence
    note("team #{team.slug} has no slack_channel set") unless channel
    channel
  end

  def owning_team(field)
    service = service_entry_for(field)
    return nil unless service

    relationship = service.outgoing_relationships.includes(target_entry: :catalog_type).detect do |rel|
      rel.target_entry.deleted_at.nil? && rel.target_entry.catalog_type.system_key == CatalogType::SYSTEM_KEY_TEAM
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

    entry = CatalogEntry.active.joins(:catalog_type)
      .where(workspace: @workspace, slug: slug)
      .find_by(catalog_types: { system_key: field.to_s })
    note("#{field} #{slug.inspect} is not in the catalog") unless entry
    @service_entries[slug] = entry
  end

  def team_entry_by_id(id)
    entry = CatalogEntry.active.where(workspace: @workspace).find_by(id: id)
    note("catalog team #{id} not found") unless entry
    entry
  end

  def note(message)
    @notes << message
  end
end
