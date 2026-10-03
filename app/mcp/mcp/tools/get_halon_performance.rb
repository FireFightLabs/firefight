module Mcp
  module Tools
    # The numbers on the Performance page, so an agent can answer how Halon has been doing.
    class GetHalonPerformance < Base
      tool_name GET_HALON_PERFORMANCE
      authorize_as Ability::Action::RESOURCE_INVESTIGATIONS
      description "How Halon has done in this workspace over the last 7, 30 or 90 days: how many investigations ran and " \
                  "reached an answer, the median time to an answer, what the team said of the answers (right, partly " \
                  "right, wrong, not rated), what came of its fixes, and the answers marked wrong with what Halon learned " \
                  "from each incident. Read from what the team recorded, never estimated. Docs: #{Docs::MCP_SERVER}"
      annotations(**READ_ONLY)
      input_schema(
        properties: {
          days: { type: "integer", enum: Investigation::Performance::WINDOWS, description: "The window in days. 30 when not given" }
        }
      )

      def self.perform(workspace:, args:)
        unavailable = Investigation.unavailable_reason(workspace)
        return Mcp::ToolDispatcher.error_response(unavailable) if unavailable

        performance = Investigation::Performance.new(workspace, days: args[:days] || Investigation::Performance::DEFAULT_WINDOW)
        verdicts = performance.verdicts
        fixes = performance.fixes

        respond(
          days: performance.days, since: performance.since.iso8601,
          investigations: { ran: performance.runs_count, ended: performance.ended_count, answered: performance.answered_count,
                            median_seconds_to_answer: performance.median_seconds },
          answers: { rated: performance.rated_count, right: verdicts[Investigation::Finding::OUTCOME_CONFIRMED],
                     partly_right: verdicts[Investigation::Finding::OUTCOME_PARTIAL], wrong: verdicts[Investigation::Finding::OUTCOME_WRONG],
                     not_rated: verdicts[Investigation::Performance::NOT_RATED] },
          fixes: fixes.to_h,
          marked_wrong: performance.mistakes.map { |mistake| mistake_payload(mistake) }
        )
      end

      def self.mistake_payload(mistake)
        finding = mistake.finding
        { investigation: finding.investigation_id, incident: finding.investigation.incident&.identifier, answer: finding.summary,
          cause: finding.winning_hypothesis&.assertion, marked_at: finding.outcome_at&.iso8601,
          lessons: mistake.lessons.map(&:lesson) }
      end
      private_class_method :mistake_payload
    end
  end
end
