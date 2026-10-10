module Mcp
  module Tools
    # What Halon raised on its own, from the checks it runs on a schedule and the security events that start it, newest
    # first, with when it was said and why one is still waiting to be said.
    class ListNotices < Base
      tool_name LIST_NOTICES
      authorize_as Ability::Action::RESOURCE_MONITORING
      description "List the problems Halon raised on its own, from scheduled checks (disk space, certificates, error budget, " \
                  "cost) and security events such as a leaked secret, newest first: what each is about, how urgent, the day it " \
                  "becomes a problem, when Halon first and last said it and the run that found it. Halon says each once and " \
                  "again only when it gets worse, so use it to see whether something was already raised. Docs: #{Docs::MONITORING}"
      annotations(**READ_ONLY)
      input_schema(
        properties: {
          signal: { type: "string", enum: Investigation::Notice::SIGNALS, description: "Only this kind of problem (optional)" },
          query: { type: "string", description: "Matches what it is about or what Halon said (optional)" },
          limit: { type: "integer", description: "Max results, up to 50 (default 25)" }
        },
        required: []
      )

      def self.perform(workspace:, args:)
        scope = workspace.investigation_notices.includes(:resource, :check).recent
        scope = scope.where(signal: args[:signal]) if args[:signal].present?
        if args[:query].present?
          pattern = "%#{ActiveRecord::Base.sanitize_sql_like(args[:query])}%"
          scope = scope.where("investigation_notices.topic ILIKE :q OR investigation_notices.summary ILIKE :q", q: pattern)
        end

        notices, truncated = capped(scope, args)
        respond(notices: notices.map { |notice| summary(notice) }, truncated: truncated)
      end

      def self.summary(notice)
        {
          about: notice.topic, signal: notice.signal, severity: notice.severity, said: notice.summary,
          becomes_a_problem_on: notice.due_on&.iso8601, resource: notice.resource&.name, check: notice.check&.name,
          first_said_at: notice.first_said_at&.iso8601, last_said_at: notice.last_said_at&.iso8601, last_seen_at: notice.last_seen_at.iso8601,
          times_said: notice.times_said, not_said_because: notice.unsaid_reason, investigation_id: notice.investigation_id
        }.compact
      end
    end
  end
end
