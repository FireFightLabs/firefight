# The workspace's connection tools whole, with their connections and actions, as a chat's catalogue, a specialist, a
# watch, an investigation and the MCP server read them. Read once for everything holding this workspace while nothing
# they are read from changed, and kept across requests and jobs in Rails.cache and in each process's memory as the rows
# they were read from, keyed on those rows' versions (tool_catalogue_version), so most replies read none of them. A connection's environments hold its
# credentials, so they are never kept. They are read beside the kept rows, in one query.
module Workspace::ToolCatalogue
  extend ActiveSupport::Concern

  # Each row's id, transaction and place in its table, which every write to it moves whatever made it (save,
  # update_columns, update_all, upsert_all) and in whatever order transactions commit, so kept rows are never stale.
  ROWS_VERSION = "md5(string_agg(%<table>s.id::text || ':' || %<table>s.xmin::text || ':' || %<table>s.ctid::text, ',' ORDER BY %<table>s.id))".freeze
  TOOL_CATALOGUE_VERSION_SQL = <<~SQL.squish.freeze
    SELECT
      (SELECT #{format(ROWS_VERSION, table: 'integrations')} FROM integrations WHERE workspace_id = :workspace),
      (SELECT #{format(ROWS_VERSION, table: 'integration_tools')} FROM integration_tools
         JOIN integrations ON integrations.id = integration_tools.integration_id WHERE integrations.workspace_id = :workspace),
      (SELECT #{format(ROWS_VERSION, table: 'ability_actions')} FROM ability_actions WHERE workspace_id = :workspace AND source_type = :source_type)
  SQL

  # The kept rows are a megabyte or more for a workspace with many connections, and the shared cache sits in the database,
  # so reading them on every request crossed the network each time and took seconds. Each process keeps the newest few in
  # memory too, under the same key, so only the first request after they change reads them from the shared cache.
  IN_PROCESS = ActiveSupport::Cache::MemoryStore.new(size: 64.megabytes)

  # The tools switched on in a connection that is on, as Integration::Tool.in_workspace reads them.
  def switched_on_tools = tool_catalogue.last

  # Every tool of a connection not deleted, switched on or not, by the name the agent calls it, whole, for a caller that
  # runs one or reads its schema. Naming one or telling a read from a change reads tool_labels (Workspace::ToolLabels).
  def connection_tools_by_name
    @connection_tools_by_name ||= tool_catalogue.second.index_by(&:model_facing_name)
  end

  # What the kept rows are read from, as one value read in one query.
  def tool_catalogue_version
    query = self.class.sanitize_sql([ TOOL_CATALOGUE_VERSION_SQL, { workspace: id, source_type: Integration::Tool.polymorphic_name } ])
    self.class.with_connection { |connection| connection.select_rows(query, "Tool catalogue version").first }
  end

  private

  # [version, every tool, those switched on], built again only when the version moved.
  def tool_catalogue
    version = tool_catalogue_version
    return @tool_catalogue if @tool_catalogue&.first == version

    key = [ "workspace_tool_catalogue", id, version, self.class.tool_catalogue_shape ]
    tools = tools_from(kept_rows(key) { Rails.cache.fetch(key) { tool_catalogue_rows } })
    switched_on = tools.select { |tool| tool.enabled? && tool.available? && tool.integration.disabled_at.nil? }
    @tool_catalogue = [ version, tools.freeze, switched_on.freeze ]
  end

  # Kept in memory only beside a shared cache, so where nothing is shared, as in tests, every read is as it was.
  def kept_rows(key, &)
    Rails.cache.is_a?(ActiveSupport::Cache::NullStore) ? yield : IN_PROCESS.fetch(key, &)
  end

  # The rows as the database returned them, so a kept copy is plain values and never an object or a decrypted value.
  def tool_catalogue_rows
    integrations = self.integrations.where(deleted_at: nil)
    tools = Integration::Tool.where(integration_id: integrations.select(:id)).order(:id)
    actions = Ability::Action.where(workspace_id: id, source_type: Integration::Tool.polymorphic_name, source_id: tools.select(:id))
    self.class.with_connection do |connection|
      [ integrations, tools, actions ].map { |relation| connection.select_all(relation.arel, "Tool catalogue").then { |result| [ result.columns, result.rows ] } }
    end
  end

  def tools_from((integration_rows, tool_rows, action_rows))
    integrations = instantiated(Integration, integration_rows).index_by(&:id)
    integrations.each_value { |integration| integration.association(:workspace).target = self }
    ActiveRecord::Associations::Preloader.new(records: integrations.values, associations: :integration_environments).call
    actions = instantiated(Ability::Action, action_rows).index_by(&:source_id)
    instantiated(Integration::Tool, tool_rows).map do |tool|
      action = actions[tool.id]
      tool.association(:integration).target = integrations.fetch(tool.integration_id)
      tool.association(:ability_action).target = action
      action&.association(:source)&.target = tool
      tool
    end
  end

  def instantiated(model, (columns, rows)) = rows.map { |row| model.instantiate(columns.zip(row).to_h) }

  class_methods do
    # The columns the kept rows hold, so rows kept before a migration are never read as another shape.
    def tool_catalogue_shape
      @tool_catalogue_shape ||= Digest::MD5.hexdigest([ Integration, Integration::Tool, Ability::Action ].map(&:column_names).to_json)
    end
  end
end
