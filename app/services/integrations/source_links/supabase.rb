module Integrations
  module SourceLinks
    # A Supabase result links to the dashboard page of the project the call named, on the page its answer lives on.
    # That is the migrations, the branches, the Postgres or API logs, or the project itself, at the pages Supabase's
    # documentation links to under dashboard/project/<ref>, in guides/observability/logs, guides/platform/read-replicas
    # and troubleshooting/branch-in-migrations-failed-status. A connection scoped to one project names it on its server
    # address as project_ref, and its tools take no project, so the address is read instead.
    class Supabase
      PROVIDER = MapReaders::Supabase::PROVIDER
      NAME = MapReaders::Supabase::NAME
      REF = /\A[a-z0-9]{1,40}\z/
      GET_PROJECT = Capabilities::Supabase::TOOLS.fetch(Capabilities::STATUS)
      GET_LOGS = "get_logs".freeze
      LOGS_PAGE = "logs".freeze
      PAGES = {
        "list_migrations" => Capabilities::Supabase::MIGRATIONS_PAGE, "apply_migration" => Capabilities::Supabase::MIGRATIONS_PAGE,
        "list_branches" => "branches", "query_logs" => LOGS_PAGE
      }.freeze
      # get_logs reads one service, and these have a page of their own.
      SERVICE_PAGES = { "postgres" => "logs/postgres-logs", "api" => "logs/edge-logs" }.freeze

      def initialize(settings)
        @settings = settings
      end

      def link(tool_name:, arguments:, text: "")
        asked = arguments.to_h.stringify_keys
        ref = (asked[Capabilities::Supabase::PROJECT_ID] || (asked["id"] if tool_name == GET_PROJECT) || scoped).to_s[REF]
        return unless ref

        page = tool_name == GET_LOGS ? SERVICE_PAGES.fetch(asked["service"].to_s, LOGS_PAGE) : PAGES[tool_name]
        Telemetry::Link.new(provider: page ? "#{NAME}, on its #{page.split('/').last.tr('-', ' ')} page" : NAME, url: MapReaders::Supabase.page(ref, page))
      end

      private

      def scoped
        Rack::Utils.parse_query(URI.parse(@settings.server_url.to_s).query.to_s)[Capabilities::Supabase::SCOPED_TO]
      rescue URI::InvalidURIError
        nil
      end
    end
  end
end
