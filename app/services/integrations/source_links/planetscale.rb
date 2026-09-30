module Integrations
  module SourceLinks
    # A PlanetScale result links to its branch, or its database, as PlanetScale named that page itself. The address is
    # the html_url the map sweep read from PlanetScale, never one pieced together here, so a link never points at a page
    # that does not exist. Before the first sweep there is no address to give, and the result says so.
    class Planetscale
      PROVIDER = "planetscale".freeze
      NAME = "PlanetScale".freeze
      # The tab on the branch page a tool's answer lives on, as PlanetScale's documentation names it.
      TABS = {
        "planetscale_get_insights" => "Insights",
        "planetscale_list_query_error_patterns" => "Insights",
        "planetscale_list_query_error_executions" => "Insights",
        "planetscale_list_query_tags" => "Insights",
        "planetscale_list_query_tag_summaries" => "Insights",
        "planetscale_get_query_tag" => "Insights",
        "planetscale_execute_read_query" => "Console"
      }.freeze

      def initialize(workspace)
        @workspace = workspace
      end

      def link(tool_name:, arguments:, text: "")
        where = arguments.to_h.stringify_keys
        where = where.merge(where["pathParameters"].to_h.stringify_keys) if where["pathParameters"].is_a?(Hash)
        organization, database, branch = where.values_at("organization", "database", "branch")
        return if organization.blank? || database.blank?

        page = (resource(organization, ResourceMap::KIND_BRANCH, "#{database}/#{branch}") if branch.present?) ||
               resource(organization, ResourceMap::KIND_DATABASE, database)
        return unless page&.url.present?

        tab = TABS[tool_name]
        Telemetry::Link.new(provider: tab ? "#{NAME}, on the #{tab} tab" : NAME, url: page.url)
      end

      private

      def resource(organization, kind, external_id)
        ResourceMap::Resource.present.find_by(workspace: @workspace, provider: PROVIDER, account: organization, kind: kind, external_id: external_id)
      end
    end
  end
end
