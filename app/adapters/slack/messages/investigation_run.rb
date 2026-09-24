module Slack
  module Messages
    # Named for the run, since a bare Investigation here would shadow the model.
    module InvestigationRun
      SECTION_TEXT_LIMIT = 3000
      EVIDENCE_LIMIT = 6
      SOURCES_SHOWN = 3

      # A question with no incident is named by its own words, which came from a person and are escaped.
      def self.started(incident:, started_by:, question: nil)
        title = incident ? incident.identifier : "\"#{Mrkdwn.escape(question.to_s.truncate(200))}\""
        [
          {
            type: "section",
            text: {
              type: "mrkdwn",
              text: ":mag: *Investigating #{title}*\n" \
                    "#{started_by.present? ? "Started by #{Mrkdwn.escape(started_by)}. " : ''}I will post what I find in this thread."
            }
          }
        ]
      end

      def self.started_text(incident:, question:)
        incident ? "Investigating #{incident.identifier}" : "Investigating: #{question.to_s.truncate(200)}"
      end

      # The answer that led someone to declare this incident, so whoever joins the channel starts from it.
      def self.carried_over(finding:)
        question = finding.investigation.question
        intro = ":mag: *Declared from an investigation*" \
                "#{question.present? ? " into \"#{Mrkdwn.escape(question.to_s.truncate(200))}\"" : ''}. This is what it found."
        [ { type: "section", text: { type: "mrkdwn", text: intro } }, *finding(finding: finding) ]
      end

      def self.finding(finding:)
        blocks = [ { type: "section", text: { type: "mrkdwn", text: summary_text(finding) } } ]
        blocks << evidence_block(finding) if finding.evidence_items.any?
        blocks << gaps_block(finding) if finding.gaps.present?
        actions = action_block(finding)
        blocks << actions if actions
        blocks << feedback_block(finding)
        blocks
      end

      # The button is offered only when running it again could end differently.
      def self.stopped(reason:, rerun: nil, rerun_question: nil, investigation: nil)
        blocks = [ { type: "section", text: { type: "mrkdwn", text: ":warning: *Stopped without an answer.* #{reason}." } } ]
        blocks << rerun_block(rerun) if rerun
        blocks << rerun_question_block(rerun_question) if rerun_question
        link = investigation && open_block(investigation)
        blocks << link if link
        blocks
      end

      # Every step, theory and receipt of the run are on its page, which the thread only summarises.
      def self.open_block(investigation)
        button = open_button(investigation)
        button && { type: "actions", elements: [ button ] }
      end

      # An answer that says users are hurt now, with no incident yet, offers to declare one first.
      def self.action_block(finding)
        investigation = finding.investigation
        elements = [
          (declare_button(investigation) if finding.suggests_incident && investigation.incident.nil?),
          open_button(investigation)
        ].compact
        elements.any? ? { type: "actions", elements: elements } : nil
      end

      def self.open_button(investigation)
        url = DashboardUrl.investigation(investigation)
        url && { type: "button", text: { type: "plain_text", text: "Open in Firefight" }, url: url }
      end

      def self.declare_button(investigation)
        {
          type: "button", style: "danger", text: { type: "plain_text", text: "Declare incident" },
          action_id: Identifiers::DECLARE_INCIDENT_FROM_INVESTIGATION, value: investigation.id
        }
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

      # A question asked again, in the same place, by whoever presses it.
      def self.rerun_question_block(investigation)
        {
          type: "actions",
          elements: [
            {
              type: "button",
              text: { type: "plain_text", text: ":mag: Run again", emoji: true },
              action_id: Identifiers::RERUN_INVESTIGATION_QUESTION,
              value: investigation.id
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
