module Integrations
  module ReadGuards
    # Sentry's server lists a few tools itself and keeps the rest in a catalog, run through execute_sentry_tool with the
    # catalog tool's name in name and its parameters in arguments (getsentry/sentry-mcp,
    # packages/mcp-core/src/tools/special/execute-tool.ts). The server marks execute_sentry_tool destructive whatever it
    # runs, yet it is the only way to the catalog's reads, such as an issue's details, an event's stack trace and a
    # trace. A call is a read when the tool it names is one the server's own definition marks readOnlyHint
    # (packages/mcp-core/src/tools/catalog), and any other name counts as a change.
    module Sentry
      TOOL = "execute_sentry_tool".freeze
      NAME = "name".freeze
      READS = %w[
        find_alert_rules find_dashboards find_dsns find_metric_monitors find_monitors find_organizations find_projects
        find_releases find_teams find_uptime_monitors
        get_agent_conversation_details get_alert_options get_alert_rule get_dashboard_details get_doc get_event_attachment get_event_stacktrace
        get_issue_activity get_issue_breadcrumbs get_issue_details get_issue_tag_values get_issue_user_reports get_latest_base_snapshot
        get_metric_monitor_details get_monitor_details get_profile get_profile_details get_release_details get_replay_details get_sentry_mcp_info
        get_sentry_resource get_snapshot get_snapshot_image get_span_details get_trace_details get_uptime_monitor_details
        search_agent_conversations search_docs search_issue_events search_issues whoami
        search_errors search_events search_logs search_metrics search_profiles search_replays search_traces
      ].freeze

      def self.guards?(tool_name) = tool_name == TOOL

      # The tool's own schema serves, since the name it takes says what runs.
      def self.schema = nil

      def self.reads?(_tool_name, arguments) = READS.include?(arguments.to_h.stringify_keys[NAME].to_s)

      def self.reading(tool_name, arguments)
        return arguments if reads?(tool_name, arguments)

        named = arguments.to_h.stringify_keys[NAME].to_s
        raise PolicyRefusal, "#{named.presence || 'A catalog tool without a name'} can change things in Sentry, so it is not used while investigating."
      end
    end
  end
end
