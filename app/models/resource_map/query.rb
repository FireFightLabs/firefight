# Finds resources on a workspace's map by what they are, where they run and who owns them, a page at a time. Paging
# is keyset, so a page costs the same at the end of a large map as at its start, and the cursor is opaque. within is
# the set of resources the reader may see, all of the workspace's when nil.
class ResourceMap::Query
  SORT_NAME = "name".freeze
  # Direct dependents, the resources with a link into this one that is a fact, along a runtime relation.
  SORT_DEPENDENTS = "dependents".freeze
  SORTS = [ SORT_NAME, SORT_DEPENDENTS ].freeze
  PAGE_SIZE = 50
  MAX_PAGE_SIZE = 200
  # Counting past this costs more than the number is worth, so the total says "10,000+" instead.
  COUNT_CAP = 10_000
  NAME_ORDER = 'lower(resource_map_resources.name) COLLATE "C"'.freeze

  FILTERS = %i[provider kind account environment status health owner catalog_entry tag fields changed_since name_prefix].freeze

  InvalidCursor = Class.new(ArgumentError)

  Page = Data.define(:resources, :next_cursor, :total, :capped) do
    def total_label = "#{ActiveSupport::NumberHelper.number_to_delimited(total)}#{'+' if capped}"
  end

  attr_reader :workspace, :sort

  # provider, kind, account and status take one value or several. tag is "key" (the tag is set) or "key=value", or a
  # hash of them, a nil value meaning only that the key is set. fields match details exactly ({ "engine" => "postgres 16" }).
  # owner is a team catalog entry, catalog_entry any entry, each a record or an id.
  def initialize(workspace, within: nil, provider: nil, kind: nil, account: nil, environment: nil, status: nil, health: nil, owner: nil,
                 catalog_entry: nil, tag: nil, fields: nil, include_removed: false, changed_since: nil, name_prefix: nil, sort: SORT_NAME)
    raise ArgumentError, "sort is one of #{SORTS.join(', ')}" unless SORTS.include?(sort)

    @workspace = workspace
    @within = within
    @filters = { provider:, kind:, account:, environment:, status:, health:, owner:, catalog_entry:, tag:, fields:, changed_since:, name_prefix: }
    @include_removed = include_removed
    @sort = sort
  end

  # Every resource that matches, unordered, for counting and grouping.
  def scope
    @scope ||= begin
      relation = (@within || ResourceMap::Resource.all).where(workspace_id: workspace.id)
      relation = relation.where(removed_at: nil) unless @include_removed
      FILTERS.reduce(relation) { |filtered, name| send(:"filter_#{name}", filtered, @filters[name]) }
    end
  end

  def page(cursor: nil, limit: PAGE_SIZE)
    size = limit.to_i.clamp(1, MAX_PAGE_SIZE)
    found = listing(cursor: cursor, limit: size + 1).to_a
    shown = found.first(size)
    total, capped = count
    Page.new(resources: shown, next_cursor: (encode(shown.last) if found.size > size), total: total, capped: capped)
  end

  # The rows of one page in order, one past the page to know whether another follows.
  def listing(cursor:, limit:) = after(ordered, cursor).limit(limit)

  # The exact count up to COUNT_CAP, and whether there were more.
  def count
    counted = scope.limit(COUNT_CAP + 1).count
    [ [ counted, COUNT_CAP ].min, counted > COUNT_CAP ]
  end

  # Fact links into a resource from present ones, along the relations a failure travels. Only dependents inside within
  # count, so a reader is never told how many resources it cannot see depend on one.
  def self.dependents_sql(resource_column, within: nil)
    suggestions = ResourceMap::SUGGESTION_ORIGINS.map { |origin| ActiveRecord::Base.connection.quote(origin) }.join(", ")
    relations = ResourceMap::RUNTIME_RELATIONS.map { |relation| ActiveRecord::Base.connection.quote(relation) }.join(", ")
    "(SELECT count(*) FROM resource_map_links dependent_links " \
      "JOIN resource_map_resources dependents ON dependents.id = dependent_links.from_resource_id AND dependents.removed_at IS NULL " \
      "WHERE dependent_links.to_resource_id = #{resource_column} AND dependent_links.dismissed_at IS NULL " \
      "AND dependent_links.relation IN (#{relations}) " \
      "AND (dependent_links.origin NOT IN (#{suggestions}) OR dependent_links.confirmed_at IS NOT NULL)" \
      "#{" AND dependents.id IN (#{within.select(:id).to_sql})" if within})"
  end

  private

  def ordered
    return scope.order(Arel.sql(NAME_ORDER), :id) if sort == SORT_NAME

    counted = scope.select("resource_map_resources.*, #{self.class.dependents_sql('resource_map_resources.id', within: @within)} AS dependents_count")
    ResourceMap::Resource.from(counted, :resource_map_resources).order(dependents_count: :desc, id: :asc)
  end

  def after(relation, cursor)
    return relation if cursor.blank?

    sorted, value, id = decode(cursor)
    raise InvalidCursor, "This cursor belongs to a #{sorted} sort." unless sorted == sort

    if sort == SORT_NAME
      relation.where("(#{NAME_ORDER}, resource_map_resources.id) > (? COLLATE \"C\", ?::uuid)", value.to_s, id)
    else
      relation.where("resource_map_resources.dependents_count < :count OR (resource_map_resources.dependents_count = :count AND resource_map_resources.id > :id::uuid)",
                     count: value.to_i, id: id)
    end
  end

  def encode(resource)
    value = sort == SORT_NAME ? resource.name.downcase : resource.dependents_count
    Base64.urlsafe_encode64([ sort, value, resource.id ].to_json, padding: false)
  end

  def decode(cursor)
    sorted, value, id = JSON.parse(Base64.urlsafe_decode64(cursor.to_s))
    raise InvalidCursor, "This cursor is not one a page gave." unless sorted.is_a?(String) && id.to_s.match?(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)

    [ sorted, value, id ]
  rescue ArgumentError, JSON::ParserError
    raise InvalidCursor, "This cursor is not one a page gave."
  end

  def filter_provider(relation, value) = value.blank? ? relation : relation.where(provider: Array(value))

  def filter_kind(relation, value) = value.blank? ? relation : relation.where(kind: Array(value))

  def filter_account(relation, value) = value.blank? ? relation : relation.where(account: Array(value))

  def filter_status(relation, value)
    return relation if value.blank?

    relation.where("lower(resource_map_resources.status) IN (?)", Array(value).map { |status| status.to_s.downcase })
  end

  # Health is read off the status the same way ResourceMap::Resource#health reads it, so unknown is a status in no list.
  def filter_health(relation, value)
    return relation if value.blank?

    healths = Array(value).map(&:to_s)
    words = ResourceMap::Resource::STATUS_HEALTH.select { |_, health| healths.include?(health) }.keys
    known = relation.where("lower(resource_map_resources.status) IN (?)", words.presence || [ "" ])
    return known unless healths.include?(ResourceMap::Resource::HEALTH_UNKNOWN)

    unknown = relation.where("resource_map_resources.status IS NULL OR lower(resource_map_resources.status) NOT IN (?)", ResourceMap::Resource::STATUS_HEALTH.keys)
    words.empty? ? unknown : known.or(unknown)
  end

  # The environment the connection that reported it is wired to, by name.
  def filter_environment(relation, value)
    return relation if value.blank?

    rows = IntegrationEnvironment.joins(:integration, :environment).where(integrations: { workspace_id: workspace.id })
                                 .where("lower(catalog_entries.name) IN (?)", Array(value).map { |name| name.to_s.downcase })
    relation.where(integration_environment_id: rows.select(:id))
  end

  # What a team owns: the resources linked to the team itself, or to a catalog entry that names the team as an owner.
  def filter_owner(relation, value)
    return relation if value.blank?

    team = CatalogEntry.where(workspace: workspace, deleted_at: nil).joins(:catalog_type)
                       .find_by(catalog_types: { system_key: CatalogType::SYSTEM_KEY_TEAM }, id: entry_id(value))
    return relation.none unless team

    owned = CatalogEntryRelationship.where(target_entry_id: team.id).select(:source_entry_id)
    relation.where(id: linked_to(CatalogEntry.where(id: team.id).or(CatalogEntry.where(id: owned))))
  end

  def filter_catalog_entry(relation, value)
    value.blank? ? relation : relation.where(id: linked_to(CatalogEntry.where(id: entry_id(value))))
  end

  def linked_to(entries)
    ResourceMap::EntryLink.where(workspace_id: workspace.id, catalog_entry_id: entries.where(workspace: workspace, deleted_at: nil).select(:id)).select(:resource_id)
  end

  def entry_id(value) = value.is_a?(CatalogEntry) ? value.id : value

  # A tag with a value is containment, which the details index answers. A tag named alone is a JSON path, which it
  # answers too, unlike the key-exists operator.
  def filter_tag(relation, value)
    return relation if value.blank?

    tags(value).reduce(relation) do |filtered, (key, wanted)|
      if wanted.nil?
        filtered.where("resource_map_resources.details @? CAST(:path AS jsonpath)", path: "$.#{ResourceMap::TAGS}.#{key.to_json}")
      else
        filtered.where("resource_map_resources.details @> ?::jsonb", { ResourceMap::TAGS => { key => wanted } }.to_json)
      end
    end
  end

  def tags(value)
    return value.to_h { |key, wanted| [ key.to_s, wanted&.to_s ] } if value.is_a?(Hash)

    Array(value).to_h do |each|
      key, wanted = each.to_s.split("=", 2)
      [ key.strip, wanted&.strip ]
    end
  end

  def filter_fields(relation, value)
    value.blank? ? relation : relation.where("resource_map_resources.details @> ?::jsonb", value.to_h.transform_keys(&:to_s).to_json)
  end

  def filter_changed_since(relation, value)
    return relation if value.blank?

    relation.where(id: ResourceMap::Change.where(workspace_id: workspace.id, happened_at: value..).select(:resource_id))
  end

  def filter_name_prefix(relation, value)
    return relation if value.blank?

    relation.where("#{NAME_ORDER} LIKE ?", "#{ResourceMap::Resource.sanitize_sql_like(value.to_s.strip.downcase)}%")
  end
end
