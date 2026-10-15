# What a page or a step needs to name a connection's tool and tell a read from a change: the tool's name, whether it
# only reads, whether it is switched on, and its connection's name, slug and provider. Read as a few columns in one
# query, never the tools' schemas or their connections' environments, and cached on what they are read from
# (Workspace#reach_version), which every change to a connection or a tool moves, so a label is never stale.
module Workspace::ToolLabels
  extend ActiveSupport::Concern

  # The connection a label names.
  Connection = Data.define(:id, :name, :slug, :provider) do
    def display_name = Integration.display_name_for(name, provider)
  end

  # One tool of a connection not deleted, as Integration::Tool answers the same questions, so a read guard reads either.
  Label = Data.define(:name, :read_only, :switched_on, :integration) do
    def read_only? = read_only
    def switched_on? = switched_on
    def model_facing_name = "#{integration.slug}.#{name}".tr(".", "_")
  end

  COLUMNS = [ "integration_tools.name", "integration_tools.read_only",
              Arel.sql("integration_tools.enabled AND integration_tools.removed_at IS NULL AND integrations.disabled_at IS NULL"),
              "integrations.id", "integrations.name", "integrations.slug", "integrations.provider" ].freeze

  # Every tool of a connection not deleted, switched on or not, by the name the agent calls it. Memoized, since a page
  # of chat messages names each step's tool.
  def tool_labels
    @tool_labels ||= Rails.cache.fetch([ "workspace_tool_labels", id, reach_version(nil) ]) { read_tool_labels }.then do |rows|
      connections = {}
      rows.to_h do |name, read_only, switched_on, *connection|
        integration = connections[connection.first] ||= Connection.new(*connection)
        label = Label.new(name: name, read_only: read_only, switched_on: switched_on, integration: integration)
        [ label.model_facing_name, label ]
      end
    end
  end

  # Memoized for the same reason, since a page asks whether each step only read.
  def reading_tool_names
    @reading_tool_names ||= tool_labels.values.select { |label| label.switched_on? && label.read_only? }.to_set(&:model_facing_name)
  end

  private

  def read_tool_labels = Integration::Tool.joins(:integration).where(integrations: { workspace_id: id, deleted_at: nil }).pluck(*COLUMNS)
end
