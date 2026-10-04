module Integrations
  module SourceLinks
    # A Supabase result links to the dashboard page of the project the call named, on the page its answer lives on.
    # That is the migrations, the branches, the Postgres or API logs, or the project itself, at the pages Supabase's
    # documentation links to under dashboard/project/<ref>, in guides/observability/logs, guides/platform/read-replicas
    # and troubleshooting/branch-in-migrations-failed-status. A connection scoped to one project names it in its
    # project_ref connect field, and its tools take no project, so that field is read instead. The dashboard is the
    # registry's site.
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
        return unless ref && @settings.site

        page = tool_name == GET_LOGS ? SERVICE_PAGES.fetch(asked["service"].to_s, LOGS_PAGE) : PAGES[tool_name]
        Telemetry::Link.new(provider: page ? "#{NAME}, on its #{page.split('/').last.tr('-', ' ')} page" : NAME, url: MapReaders::Supabase.page(@settings.site, ref, page))
      end

      private

      def scoped = @settings.field(Capabilities::Supabase::SCOPED_TO)
    end
  end
end
