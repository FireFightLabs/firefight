module Slack
  module Messages
    # Named for the run, since a bare Investigation here would shadow the model.
    module InvestigationRun
      SECTION_TEXT_LIMIT = 3000
      EVIDENCE_LIMIT = 6
      SOURCES_SHOWN = 3

      def self.started(incident:, started_by:)
        [
          {
            type: "section",
            text: {
              type: "mrkdwn",
              text: ":mag: *Investigating #{incident.identifier}*\n" \
                    "#{started_by.present? ? "Started by #{started_by}. " : ''}I will post what I find in this thread."
            }
          }
        ]
      end

      def self.finding(finding:)
        blocks = [ { type: "section", text: { type: "mrkdwn", text: summary_text(finding) } } ]
        blocks << evidence_block(finding) if finding.evidence_items.any?
        blocks << gaps_block(finding) if finding.gaps.present?
        blocks << feedback_block(finding)
        blocks
      end

      # The button is offered only when running it again could end differently.
      def self.stopped(reason:, rerun: nil)
        blocks = [ { type: "section", text: { type: "mrkdwn", text: ":warning: *Stopped without an answer.* #{reason}." } } ]
        blocks << rerun_block(rerun) if rerun
        blocks
      end

      def self.rerun_block(incident)
        {
          type: "actions",
          elements: [
            {
              type: "button",
              text: { type: "plain_text", text: ":mag: Run again", emoji: true },
              action_id: Identifiers::START_INVESTIGATION,
              value: incident.id
            }
          ]
        }
      end

      def self.summary_text(finding)
        Formatting.markdown_to_mrkdwn(finding.summary.to_s).truncate(SECTION_TEXT_LIMIT)
      end

      def self.evidence_block(finding)
        lines = finding.evidence_items.first(EVIDENCE_LIMIT).map { |item| evidence_line(item) }
        {
          type: "section",
          text: { type: "mrkdwn", text: "*Why I think so*\n#{lines.join("\n")}".truncate(SECTION_TEXT_LIMIT) }
        }
      end

      # The claim, then what it rests on, so a reader sees where each line came from.
      def self.evidence_line(item)
        sources = item.source_labels.first(SOURCES_SHOWN).join(", ")
        line = "• #{Formatting.markdown_to_mrkdwn(item.claim)}"
        sources.present? ? "#{line} _(#{Formatting.markdown_to_mrkdwn(sources)})_" : line
      end

      def self.gaps_block(finding)
        {
          type: "context",
          elements: [ { type: "mrkdwn", text: "*Could not check:* #{finding.gaps}".truncate(SECTION_TEXT_LIMIT) } ]
        }
      end

      # Slack's own feedback element, so the buttons look and behave like every other agent's.
      def self.feedback_block(finding)
        {
          type: "context_actions",
          elements: [
            {
              type: "feedback_buttons",
              action_id: Identifiers::INVESTIGATION_FEEDBACK,
              positive_button: {
                text: { type: "plain_text", text: "Right" },
                value: "#{finding.id}:#{Investigation::Finding::OUTCOME_CONFIRMED}",
                accessibility_label: "This answer was right"
              },
              negative_button: {
                text: { type: "plain_text", text: "Wrong" },
                value: "#{finding.id}:#{Investigation::Finding::OUTCOME_WRONG}",
                accessibility_label: "This answer was wrong"
              }
            }
          ]
        }
      end
    end
  end
end
