module Slack
  module Messages
    # What Halon says on its own in an incident an alert opened: that it acted under an unattended rule and how to undo
    # it, that a rule covered the fix but it did not act, or that it did not start on the alert.
    module OnCall
      ACTED_TITLE = ":zap:  *Halon acted on its own*".freeze
      NOT_ACTED_TITLE = ":pause_button:  *Halon did not act on its own*".freeze
      HELD_TITLE = ":mag:  *Halon did not start*".freeze

      def self.unattended(note)
        note.acted ? acted(note) : not_acted(note)
      end

      def self.unattended_fallback(note)
        return "Halon acted on its own: #{note.plan.summary}" if note.acted

        "Halon did not act on its own. #{note.reason}"
      end

      def self.acted(note)
        plan = note.plan
        undo = plan.steps.select(&:runs_itself?).filter_map { |step| "> Step #{step.position}: #{Mrkdwn.escape(step.undo)}" if step.undo.present? }
        [
          { type: "section", text: { type: "mrkdwn", text: ACTED_TITLE } },
          { type: "divider" },
          { type: "section", text: { type: "mrkdwn", text: "Applying the fix: #{Mrkdwn.escape(plan.summary)}".truncate(Formatting::SECTION_TEXT_LIMIT) } },
          { type: "section", text: { type: "mrkdwn", text: rules_text(note).truncate(Formatting::SECTION_TEXT_LIMIT) } },
          { type: "section", text: { type: "mrkdwn", text: [ "*To undo it*", *undo, UNDO_HINT ].join("\n").truncate(Formatting::SECTION_TEXT_LIMIT) } },
          { type: "context", elements: [ { type: "mrkdwn", text: "Each call is in the activity log. Turn a rule off under Halon, On-call." } ] }
        ]
      end

      UNDO_HINT = "Press Undo fix on the fix's progress once it ends, and Halon writes the steps that put it back.".freeze

      def self.not_acted(note)
        [
          { type: "section", text: { type: "mrkdwn", text: NOT_ACTED_TITLE } },
          { type: "divider" },
          { type: "section", text: { type: "mrkdwn", text: "#{Mrkdwn.escape(note.reason)} #{Investigation::Unattended::WAITS}".truncate(Formatting::SECTION_TEXT_LIMIT) } },
          { type: "context", elements: [ { type: "mrkdwn", text: rules_text(note).truncate(Formatting::SECTION_TEXT_LIMIT) } ] }
        ]
      end

      # Each rule in the team's words, who set it, and what Halon read for it.
      def self.rules_text(note)
        lines = note.rules.each_with_index.map do |rule, index|
          set_by = " Set by #{Mrkdwn.mention(rule.created_by)}." if rule.created_by
          reading = " #{Mrkdwn.escape(note.readings[index])}" if note.readings[index]
          "Unattended rule: #{Mrkdwn.escape(rule.sentence)}#{set_by}#{reading}"
        end
        lines.join("\n")
      end

      def self.held(incident:, reason:, rerun:)
        blocks = [
          { type: "section", text: { type: "mrkdwn", text: HELD_TITLE } },
          { type: "divider" },
          { type: "section", text: { type: "mrkdwn", text: Mrkdwn.escape(reason) } }
        ]
        return blocks unless rerun

        blocks << {
          type: "actions",
          elements: [ { type: "button", text: { type: "plain_text", text: ":mag: Investigate", emoji: true }, action_id: Identifiers::START_INVESTIGATION, value: incident.id } ]
        }
      end
    end
  end
end
