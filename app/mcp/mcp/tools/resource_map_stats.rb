module Mcp
  module Tools
    # The map in numbers, narrowed by find_resources' filters, with how its connections and suggestions stand.
    class ResourceMapStats < Base
      # What a group of resources with no value is called.
      UNSET = { ResourceMap::Stats::BY_ENVIRONMENT => GetResourceMap::NO_ENVIRONMENT, ResourceMap::Stats::BY_STATUS => "no status" }.freeze

      tool_name RESOURCE_MAP_STATS
      authorize_as Ability::Action::RESOURCE_MAP
      description "The resource map in numbers: how many resources by provider, kind, account, environment, status or " \
                  "health, narrowed by the same filters as find_resources, with each connection's last sweep, error and " \
                  "what it could not read, how many suggested links wait on a person, and what changed in the last day " \
                  "by kind of change. Only what runs in the environments the caller may read is counted. Docs: #{Docs::MCP_SERVER}"
      annotations(**READ_ONLY)
      choice :environment, from: ->(workspace) { workspace.environment_entries }
      choice :provider, from: MapFilters::PROVIDERS
      input_schema(
        properties: MapFilters::PROPERTIES.merge(
          group_by: { type: "string", enum: ResourceMap::Stats::DIMENSIONS, description: "What to count by. provider by default" }
        )
      )

      def self.perform_with_principal(workspace:, principal:, args:)
        visible = ResourceMap::Resource.visible_to(principal, workspace)
        by = args[:group_by].presence || ResourceMap::Stats::BY_PROVIDER
        stats = ResourceMap::Stats.new(workspace, within: visible, **MapFilters.from(workspace, args))
        respond(
          resources: stats.total, group_by: by, groups: groups(stats.counts(by), by),
          connections: stats.connections.map { |connection| connection_line(connection) },
          suggestions_to_review: stats.suggestions_to_review, changes_last_day: stats.recent_changes
        )
      rescue MapFilters::Refused => refusal
        Mcp::ToolDispatcher.error_response(refusal.message)
      end

      # An account is counted with its provider, since two providers can name the same account.
      def self.groups(counts, by)
        counts.map do |value, count|
          name = by == ResourceMap::Stats::BY_ACCOUNT ? value.join(" ") : value
          { value: name || UNSET.fetch(by, "none"), count: count }
        end
      end

      def self.connection_line(connection)
        {
          connection: connection.environment_row.integration.name, environment: connection.environment_row.environment&.name,
          swept: connection.swept_at&.iso8601, error: connection.error, gaps: connection.gaps.presence
        }.compact
      end
    end
  end
end
