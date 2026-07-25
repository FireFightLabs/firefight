module Mcp
  module Tools
    class SearchRunbooks < Base
      tool_name SEARCH_RUNBOOKS
      authorize_as ApiKey::RESOURCE_RUNBOOKS
      description "Search this workspace's incident response runbooks: documented procedures " \
                  "for handling incidents (e.g. how to fail over a database, roll back a deploy). " \
                  "Matches name and summary. Use get_runbook for the full step-by-step content. " \
                  "Docs: #{Docs::RUNBOOKS}"
      annotations(**READ_ONLY)
      input_schema(
        properties: {
          query: { type: "string", description: "Matches runbook name or summary" },
          limit: { type: "integer", description: "Max results, up to 50 (default 25)" }
        },
        required: []
      )

      def self.perform(workspace:, args:)
        scope = workspace.runbooks.active.ordered.includes(:runbook_steps)
        if args[:query].present?
          pattern = "%#{ActiveRecord::Base.sanitize_sql_like(args[:query])}%"
          scope = scope.where("runbooks.name ILIKE :q OR runbooks.summary ILIKE :q", q: pattern)
        end

        runbooks, truncated = capped(scope, args)
        respond(runbooks: runbooks.map { |runbook| summary(runbook) }, truncated: truncated)
      end

      def self.summary(runbook)
        {
          slug: runbook.slug,
          name: runbook.name,
          summary: runbook.summary,
          external_url: runbook.external_url,
          steps_count: runbook.runbook_steps.size
        }.compact
      end
    end
  end
end
