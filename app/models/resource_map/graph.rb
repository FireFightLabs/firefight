# What a resource depends on, or what depends on it, walked along the map's links in one recursive query. A link reads
# "from depends on to", so dependents are found against the links and what it depends on along them. Only present
# resources inside within are walked, and a repository a resource is managed in ends the walk there, as in
# ResourceMap::Resource#neighborhood. Suggestions count only when asked for, the way ResourceMap::Link.facts reads.
class ResourceMap::Graph
  DEPENDS_ON = "depends_on".freeze
  DEPENDENTS = "dependents".freeze
  DIRECTIONS = [ DEPENDS_ON, DEPENDENTS ].freeze
  MAX_HOPS = 25
  NODE_LIMIT = 200
  MAX_NODES = 5_000

  # Each resource reached with the fewest hops from the root, one template per direction so the SQL is fixed and every
  # value is a bound one. Rows are deduplicated by resource, hop and whether the walk ends there, so a cycle or a diamond
  # costs at most a row per resource per hop, never one per path. A bound true folds its OR away when planned.
  WALKS = [ DEPENDENTS, DEPENDS_ON ].to_h do |direction|
    near, far = direction == DEPENDENTS ? %w[from_resource_id to_resource_id] : %w[to_resource_id from_resource_id]
    step = "next.removed_at IS NULL AND next.id <> :root AND links.dismissed_at IS NULL AND links.relation IN (:relations) " \
           "AND (:suggestions OR links.origin NOT IN (:suggestion_origins) OR links.confirmed_at IS NOT NULL) " \
           "AND (:everywhere OR next.id IN (:within))"
    sql = <<~SQL.squish
      WITH RECURSIVE walk(resource_id, hop, ends) AS (
        SELECT next.id, 1, links.relation = :managed_by
        FROM resource_map_links links JOIN resource_map_resources next ON next.id = links.#{near}
        WHERE links.#{far} = :root AND #{step}
        UNION
        SELECT next.id, walk.hop + 1, links.relation = :managed_by
        FROM walk JOIN resource_map_links links ON links.#{far} = walk.resource_id
        JOIN resource_map_resources next ON next.id = links.#{near}
        WHERE walk.hop < :hops AND NOT walk.ends AND #{step}
      )
      SELECT walk.resource_id, min(walk.hop) AS hop FROM walk
      WHERE :any_kind OR EXISTS (SELECT 1 FROM resource_map_resources found WHERE found.id = walk.resource_id AND found.kind IN (:kinds))
      GROUP BY walk.resource_id
    SQL
    [ direction, sql.freeze ]
  end.freeze
  NODES = WALKS.transform_values do |walk|
    "SELECT resource_id, hop FROM (#{walk}) reached JOIN resource_map_resources ON resource_map_resources.id = reached.resource_id " \
      "ORDER BY hop, lower(resource_map_resources.name), resource_map_resources.id LIMIT :limit"
  end.freeze
  TOTALS = WALKS.transform_values { |walk| "SELECT count(*) FROM (#{walk}) reached" }.freeze
  REACHED = WALKS.transform_values { |walk| "resource_map_resources.id IN (SELECT resource_id FROM (#{walk}) reached)" }.freeze

  Node = Data.define(:resource, :hop)

  attr_reader :root, :direction, :relations, :hops, :limit

  def initialize(root, direction: DEPENDENTS, relations: nil, suggestions: false, kinds: nil, hops: MAX_HOPS, limit: NODE_LIMIT, within: nil)
    raise ArgumentError, "direction is one of #{DIRECTIONS.join(', ')}" unless DIRECTIONS.include?(direction)

    @root = root
    @direction = direction
    @relations = (Array(relations).presence || ResourceMap::RUNTIME_RELATIONS) & ResourceMap::RELATIONS
    @suggestions = suggestions
    @kinds = Array(kinds).presence
    @hops = hops.to_i.clamp(1, MAX_HOPS)
    @limit = limit.to_i.clamp(1, MAX_NODES)
    @within = within
  end

  # The nearest resources reached first, at most limit of them, each with the fewest links between it and the root.
  def nodes
    @nodes ||= begin
      found = connection.select_rows(sanitized(NODES, limit: limit))
      resources = ResourceMap::Resource.where(id: found.map(&:first)).includes(integration_environment: %i[integration environment]).index_by(&:id)
      found.map { |id, hop| Node.new(resource: resources.fetch(id), hop: hop.to_i) }
    end
  end

  def total = @total ||= connection.select_value(sanitized(TOTALS)).to_i

  def truncated = total - nodes.size

  # Every resource reached, as a relation, for counting and joining without loading them.
  def resources = ResourceMap::Resource.where(REACHED.fetch(direction), binds)

  # The links walked between the root and the nodes shown.
  def links
    ids = [ root.id, *nodes.map { |node| node.resource.id } ]
    links = ResourceMap::Link.where(from_resource_id: ids, to_resource_id: ids, relation: relations)
    (@suggestions ? links.standing : links.facts).includes(:from_resource, :to_resource, integration_environment: :integration)
  end

  # The walk as SQL, for reading its plan.
  def reached_sql = sanitized(WALKS)

  private

  def connection = ResourceMap::Resource.connection

  def sanitized(templates, **more) = ResourceMap::Resource.sanitize_sql_array([ templates.fetch(direction), binds.merge(more) ])

  def binds
    {
      root: root.id, relations: relations, suggestions: @suggestions, suggestion_origins: ResourceMap::SUGGESTION_ORIGINS,
      everywhere: @within.nil?, within: @within ? @within.select(:id) : ResourceMap::Resource.none.select(:id),
      managed_by: ResourceMap::RELATION_MANAGED_BY, hops: hops, any_kind: @kinds.nil?, kinds: @kinds || [ "" ]
    }
  end
end
