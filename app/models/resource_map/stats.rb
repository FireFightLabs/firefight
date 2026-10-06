# The map in numbers: how many resources by provider, kind, account, environment, status or health, narrowed by any of
# ResourceMap::Query's filters, with what each connection last read and what waits on a person.
class ResourceMap::Stats
  BY_PROVIDER = "provider".freeze
  BY_KIND = "kind".freeze
  BY_ACCOUNT = "account".freeze
  BY_ENVIRONMENT = "environment".freeze
  BY_STATUS = "status".freeze
  BY_HEALTH = "health".freeze
  DIMENSIONS = [ BY_PROVIDER, BY_KIND, BY_ACCOUNT, BY_ENVIRONMENT, BY_STATUS, BY_HEALTH ].freeze
  CHANGE_WINDOW = 24.hours

  Connection = Data.define(:environment_row, :swept_at, :error, :gaps)

  attr_reader :workspace

  # within, such as ResourceMap::Resource.visible_to, keeps every number to those resources, the connections that report
  # one of them, and the changes and suggestions that touch only them.
  def initialize(workspace, within: nil, **filters)
    @workspace = workspace
    @within = within
    @query = ResourceMap::Query.new(workspace, within: within, **filters)
  end

  def total = @query.scope.count

  # Counts by one dimension, largest first. An account is counted with its provider, as [provider, account], since two
  # providers can name the same account. A status is counted as its lowercase word.
  def counts(by)
    raise ArgumentError, "by is one of #{DIMENSIONS.join(', ')}" unless DIMENSIONS.include?(by)

    grouped = case by
    when BY_ACCOUNT then @query.scope.group(:provider, :account)
    when BY_ENVIRONMENT then @query.scope.left_joins(integration_environment: :environment).group("catalog_entries.name")
    when BY_STATUS then @query.scope.group(Arel.sql("lower(resource_map_resources.status)"))
    when BY_HEALTH then @query.scope.group(Arel.sql(health_sql))
    else @query.scope.group(by)
    end
    grouped.count.sort_by { |value, count| [ -count, value.to_s ] }.to_h
  end

  # Each switched-on connection that has swept the map or failed to, with what it could not read.
  def connections
    IntegrationEnvironment.joins(:integration).merge(Integration.active).where(integrations: { workspace_id: workspace.id })
                          .where("integration_environments.map_swept_at IS NOT NULL OR integration_environments.map_error IS NOT NULL")
                          .then { |rows| @within ? rows.where(reporting_sql) : rows }
                          .includes(:integration, :environment).order(:map_swept_at).map do |row|
      Connection.new(environment_row: row, swept_at: row.map_swept_at, error: row.map_error, gaps: row.map_gaps)
    end
  end

  def suggestions_to_review
    links = ResourceMap::Link.to_review.where(workspace: workspace)
    (@within ? links.where(from_resource_id: @within.select(:id), to_resource_id: @within.select(:id)) : links).count
  end

  # What changed in the last day, by kind of change.
  def recent_changes
    changes = ResourceMap::Change.where(workspace: workspace).since(CHANGE_WINDOW.ago)
    (@within ? changes.where(resource_id: @within.select(:id)) : changes).group(:kind).count
  end

  private

  def reporting_sql
    inside = @within.where(workspace_id: workspace.id).where("resource_map_resources.integration_environment_id = integration_environments.id " \
                                                            "OR resource_map_resources.sightings ? CAST(integration_environments.id AS text)")
    "EXISTS (#{inside.select(1).to_sql})"
  end

  def health_sql
    words = ResourceMap::Resource::STATUS_HEALTH.group_by(&:last).transform_values { |pairs| pairs.map(&:first) }
    connection = ResourceMap::Resource.connection
    cases = words.map do |health, listed|
      "WHEN lower(resource_map_resources.status) IN (#{listed.map { |word| connection.quote(word) }.join(', ')}) THEN #{connection.quote(health)}"
    end
    "CASE #{cases.join(' ')} ELSE #{connection.quote(ResourceMap::Resource::HEALTH_UNKNOWN)} END"
  end
end
