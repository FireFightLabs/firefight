# Links a service to the store its settings name, by comparing the digest of the address a setting points at with the
# digests of the addresses stores report for themselves (ResourceMap::Use and ResourceMap::Endpoint), or a store's
# shared domain with the tenant the user's name carries, or a reference both name exactly. An exact address is a fact,
# written as a matched link that names the settings it came from. A host many stores share is told apart by the
# database's name, which another tenant may share, so that match is only a likely suggestion, and an address two stores
# both report is a possible one for each. ResourceMap::Matcher writes those suggestions with its own.
class ResourceMap::HostMatcher
  Match = Data.define(:user, :store, :variables, :certainty, :clues)

  def initialize(workspace)
    @workspace = workspace
  end

  # Brings the matched links in line with the settings and addresses on the map now, under the matcher's lock, which
  # the caller holds. A link that still holds keeps its id. A pair a person dismissed, or already linked as a fact
  # another way, is left as it is, and an open suggestion for a pair that now matches exactly becomes the fact.
  def run!
    facts, = matches
    standing = ResourceMap::Link.where(workspace: @workspace, relation: ResourceMap::RELATION_USES, from_resource_id: facts.map { |match| match.user.id }.uniq)
                                .pluck(:from_resource_id, :to_resource_id, :origin, :confirmed_at, :dismissed_at)
    blocked = standing.reject { |*, origin, confirmed_at, dismissed_at| dismissed_at.nil? && (origin == ResourceMap::ORIGIN_MATCHED || (ResourceMap::SUGGESTION_ORIGINS.include?(origin) && confirmed_at.nil?)) }
                      .to_set { |from, to, *| [ from, to ] }
    rows = facts.reject { |match| blocked.include?([ match.user.id, match.store.id ]) }.map { |match| row(match) }
    kept = ResourceMap::Link.write_all(rows)
    ResourceMap::Link.where(workspace: @workspace, origin: ResourceMap::ORIGIN_MATCHED, relation: ResourceMap::RELATION_USES).where.not(id: kept).delete_all
    facts
  end

  # What only suggests a link, a match by a database's name on a shared host or an address several stores report.
  def suggestions = matches.last

  private

  def matches
    @matches ||= begin
      rows = ResourceMap::Use.connection.select_rows(matches_sql)
      resources = ResourceMap::Resource.where(id: rows.flat_map { |row| [ row[1], row[3] ] }.uniq).index_by(&:id)
      found = rows.group_by(&:first).flat_map { |_, matched| classify(matched, resources) }
      merged = found.group_by { |match| [ match.user.id, match.store.id, match.certainty ] }.map do |_, same|
        same.first.with(variables: same.flat_map(&:variables).uniq.sort, clues: same.flat_map(&:clues).uniq)
      end
      merged.partition { |match| match.certainty.nil? }
    end
  end

  # Each setting with the stores whose address it names, as use id, user id, variable, store id and whether only a
  # database's name told the store apart on a host other accounts share.
  def matches_sql
    ResourceMap::Use.sanitize_sql_array([ <<~SQL.squish, { workspace: @workspace.id } ])
        WITH pairs AS (
          SELECT uses.id AS use_id, endpoints.id AS endpoint_id FROM resource_map_uses uses
          JOIN resource_map_endpoints endpoints ON endpoints.workspace_id = uses.workspace_id AND endpoints.fingerprint = uses.fingerprint
                                               AND NOT endpoints.within_domain
          WHERE uses.workspace_id = :workspace
          UNION ALL
          SELECT uses.id, endpoints.id FROM resource_map_uses uses
          JOIN resource_map_endpoints endpoints ON endpoints.workspace_id = uses.workspace_id AND endpoints.fingerprint = uses.domain_fingerprint
                                               AND endpoints.within_domain
          WHERE uses.workspace_id = :workspace
        )
        SELECT DISTINCT uses.id, uses.resource_id, uses.variable, endpoints.resource_id, endpoints.shared_host AND endpoints.tenant_fingerprint IS NULL
        FROM pairs
        JOIN resource_map_uses uses ON uses.id = pairs.use_id
        JOIN resource_map_endpoints endpoints ON endpoints.id = pairs.endpoint_id
        JOIN resource_map_resources users ON users.id = uses.resource_id AND users.removed_at IS NULL
        JOIN resource_map_resources stores ON stores.id = endpoints.resource_id AND stores.removed_at IS NULL
        WHERE uses.resource_id <> endpoints.resource_id
          AND (endpoints.database_fingerprint IS NULL OR endpoints.database_fingerprint = uses.database_fingerprint)
          AND (endpoints.tenant_fingerprint IS NULL OR endpoints.tenant_fingerprint = uses.tenant_fingerprint)
    SQL
  end

  # One setting's matches. A single store at its exact address is a fact, and anything else is a suggestion.
  def classify(matched, resources)
    exact, by_database = matched.partition { |row| !row[4] }
    stores = (exact.presence || by_database).map { |row| resources[row[3]] }.uniq
    user = resources[matched.first[1]]
    variable = matched.first[2]
    stores.map do |store|
      certainty, clue = if exact.any? && stores.one?
        [ nil, "#{variable} on #{user.name} names the address #{ResourceMap.provider_name(store.provider)} reports for #{store.name}" ]
      elsif exact.any?
        [ ResourceMap::CERTAINTY_POSSIBLE, "#{variable} on #{user.name} names an address #{stores.size} stores report, #{store.name} among them" ]
      else
        [ ResourceMap::CERTAINTY_LIKELY,
          "#{variable} on #{user.name} names #{ResourceMap.provider_name(store.provider)}'s shared host and the database #{store.name}, " \
          "which another account on that host could also have" ]
      end
      Match.new(user: user, store: store, variables: [ variable ], certainty: certainty, clues: [ clue ])
    end
  end

  # The matched link for a pair, written over an open suggestion for it, so it keeps that suggestion's id.
  def row(match)
    { workspace_id: @workspace.id, from_resource_id: match.user.id, to_resource_id: match.store.id, relation: ResourceMap::RELATION_USES,
      origin: ResourceMap::ORIGIN_MATCHED, certainty: nil, variables: match.variables, clues: match.clues, last_seen_at: Time.current,
      integration_environment_id: nil }
  end
end
