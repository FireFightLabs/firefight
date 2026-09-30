module Integrations
  module SourceLinks
    # A PlanetScale result links to its branch, or its database, as PlanetScale named that page itself. The address is
    # the html_url the map sweep read from PlanetScale, never one pieced together here, so a link never points at a page
    # that does not exist. Before the first sweep there is no address to give, and the result says so.
    class Planetscale
      PROVIDER = MapReaders::Planetscale::PROVIDER
      NAME = "PlanetScale".freeze
      GET_INSIGHTS = "planetscale_get_insights".freeze
      LIST_QUERY_ERROR_PATTERNS = "planetscale_list_query_error_patterns".freeze
      LIST_QUERY_ERROR_EXECUTIONS = "planetscale_list_query_error_executions".freeze
      LIST_QUERY_TAGS = "planetscale_list_query_tags".freeze
      LIST_QUERY_TAG_SUMMARIES = "planetscale_list_query_tag_summaries".freeze
      GET_QUERY_TAG = "planetscale_get_query_tag".freeze
      EXECUTE_READ_QUERY = "planetscale_execute_read_query".freeze
      INSIGHTS = "Insights".freeze
      CONSOLE = "Console".freeze
      # The tab on the branch page a tool's answer lives on, as PlanetScale's documentation names it.
      TABS = {
        GET_INSIGHTS => INSIGHTS, LIST_QUERY_ERROR_PATTERNS => INSIGHTS, LIST_QUERY_ERROR_EXECUTIONS => INSIGHTS,
        LIST_QUERY_TAGS => INSIGHTS, LIST_QUERY_TAG_SUMMARIES => INSIGHTS, GET_QUERY_TAG => INSIGHTS, EXECUTE_READ_QUERY => CONSOLE
      }.freeze

      def initialize(workspace)
        @workspace = workspace
      end

      def link(tool_name:, arguments:, text: "")
        where = arguments.to_h.stringify_keys
        where = where.merge(where["pathParameters"].to_h.stringify_keys) if where["pathParameters"].is_a?(Hash)
        organization, database, branch = where.values_at("organization", "database", "branch")
        return if organization.blank? || database.blank?

        places = [ ([ ResourceMap::KIND_BRANCH, "#{database}/#{branch}" ] if branch.present?), [ ResourceMap::KIND_DATABASE, database ] ].compact
        url = ResourceMap::Resource.page_of(@workspace, provider: PROVIDER, account: organization, places: places)
        return unless url

        tab = TABS[tool_name]
        Telemetry::Link.new(provider: tab ? "#{NAME}, on the #{tab} tab" : NAME, url: url)
      end
    end
  end
end
