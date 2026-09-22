module Mcp
  module Tools
    # What an outside agent may read of a run. Never a step's raw output, which stays encrypted on the
    # step, and never the technical cause of a failure, which is for whoever debugs it.
    module InvestigationPayloads
      def self.summary(investigation)
        {
          id: investigation.id,
          incident: investigation.incident&.identifier,
          status: investigation.status,
          trigger: investigation.trigger_source,
          started_by: investigation.triggered_by.try(:principal_label),
          started_at: investigation.started_at&.utc&.iso8601,
          completed_at: investigation.completed_at&.utc&.iso8601,
          spent_cents: (investigation.spent_micros / 10_000.0).round(2),
          stopped_because: stopped_because(investigation)
        }.compact
      end

      def self.full(investigation)
        summary(investigation).merge(
          hypotheses: investigation.hypotheses.includes(citations: :source).map { |theory| hypothesis(theory) },
          steps: investigation.steps.where.not(position: nil).map { |step| step(step) },
          finding: investigation.finding && finding(investigation.finding)
        ).compact
      end

      def self.hypothesis(theory)
        { assertion: theory.assertion, status: theory.status, confidence: theory.confidence&.to_f, steps: positions(theory.citations) }.compact
      end

      def self.step(step)
        { position: step.position, label: step.label.presence || step.tool_name, tool: step.tool_name, status: step.status }.compact
      end

      def self.finding(finding)
        {
          summary: finding.summary,
          cause: finding.winning_hypothesis&.assertion,
          evidence: finding.evidence_items.includes(citations: :source).map do |item|
            { claim: item.claim, steps: positions(item.citations), sources: item.source_labels }
          end,
          gaps: finding.gaps,
          outcome: finding.outcome
        }.compact
      end

      def self.positions(citations)
        citations.filter_map { |citation| citation.source.try(:position) }
      end

      # The people in the thread saw a plain sentence, and so does an outside agent.
      def self.stopped_because(investigation)
        return nil unless investigation.status == Investigation::STATUS_FAILED

        cause = investigation.error_summary.to_s
        plain = Investigation::Runner::STOP_REASONS.values + [ Investigation::Runner::ENDED_WITHOUT_AN_ANSWER ]
        plain.include?(cause) ? cause : InvestigationJob::GAVE_UP
      end
    end
  end
end
