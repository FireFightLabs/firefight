module Mcp
  module Tools
    # The numbers on the Performance page, so an agent can answer how Halon has been doing.
    class GetHalonPerformance < Base
      # An agent reads more to a page than a person scrolls past on the Performance page.
      PREVENTED_PER_PAGE = 20

      tool_name FirefightTools::GET_HALON_PERFORMANCE
      authorize_as Ability::Action::RESOURCE_INVESTIGATIONS
      description "How Halon has done in this workspace over the last 7, 30 or 90 days: how many investigations ran and " \
                  "reached an answer, the median time to an answer, what the team said of the answers (right, partly " \
                  "right, wrong, not rated), what came of its fixes, and the answers marked wrong with what Halon learned " \
                  "from each incident. Also the problems its pull request reviews prevented: findings that were serious, " \
                  "or major or worse, and fixed before their pull request merged in the window, each with the pull " \
                  "request, the claim, how it would have failed, the evidence and the link to its comment, " \
                  "#{PREVENTED_PER_PAGE} to a page. Read from what the team recorded, never " \
                  "estimated. Docs: #{Docs::MCP_SERVER}"
      annotations(**READ_ONLY)
      input_schema(
        properties: {
          days: { type: "integer", enum: Investigation::Performance::WINDOWS, description: "The window in days. 30 when not given" },
          prevented_page: { type: "integer", minimum: 1, description: "Which page of prevented problems, newest merge first. 1 when not given" }
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
          marked_wrong: performance.mistakes.map { |mistake| mistake_payload(mistake) },
          problems_prevented: prevented_payload(PullRequestReview::ProblemsPrevented.new(workspace, days: performance.days), args[:prevented_page])
        )
      end

      def self.mistake_payload(mistake)
        finding = mistake.finding
        { investigation: finding.investigation_id, incident: finding.investigation.incident&.identifier, answer: finding.summary,
          cause: finding.winning_hypothesis&.assertion, marked_at: finding.outcome_at&.iso8601,
          lessons: mistake.lessons.map(&:lesson) }
      end

      def self.prevented_payload(prevented, page_number)
        page = prevented.page(page_number, per_page: PREVENTED_PER_PAGE)
        { count: prevented.count, page: page.number, next_page: page.next_page, problems: page.problems.map { |finding| problem_payload(finding) } }
      end

      def self.problem_payload(finding)
        review = finding.review
        { repository: review.repository, pull_request: review.number, pull_request_title: review.title, pull_request_url: review.url,
          merged_at: review.merged_at.iso8601, category: finding.category_label, severity: finding.severity_label, serious: finding.serious,
          claim: finding.claim, why: finding.why, failure_chain: finding.failure_chain, evidence: finding.evidence_items.map(&:to_h),
          path: finding.path, line: finding.line, fixed_in_sha: finding.fixed_in_sha, comment_url: finding.host_comment_url }
      end
      private_class_method :mistake_payload, :prevented_payload, :problem_payload
    end
  end
end
