module Slack
  module Messages
    # Named for the run, since a bare Investigation here would shadow the model.
    module InvestigationRun
      EVIDENCE_LIMIT = 6
      SOURCES_SHOWN = 3
      FIX_STEPS_SHOWN = 6
      ARGUMENTS_SHOWN = 200
      # How each kind of fix step gets done, as a person reads it.
      STEP_KINDS = {
        Investigation::RemediationStep::KIND_PULL_REQUEST => "Code change",
        Investigation::RemediationStep::KIND_ACTION => "Change through a tool",
        Investigation::RemediationStep::KIND_MANUAL => "For a person",
        Investigation::RemediationStep::KIND_PAGE_CHECK => "Page check"
      }.freeze

      # How the run's checklist marks each of its tasks.
      TASK_STATUSES = {
        Investigation::Progress::PENDING => Checklist::PENDING, Investigation::Progress::RUNNING => Checklist::IN_PROGRESS,
        Investigation::Progress::DONE => Checklist::COMPLETE, Investigation::Progress::FAILED => Checklist::ERROR
      }.freeze
      # Each kind of answer leads with its own emoji, so a channel tells them apart at a glance.
      ANSWER_EMOJI = {
        Investigation::Finding::KIND_ROOT_CAUSE => ":dart:", Investigation::Finding::KIND_LIKELY_CAUSE => ":mag:",
        Investigation::Finding::KIND_NO_CAUSE => ":grey_question:"
      }.freeze
      QUESTION_SHOWN = 100
      WRONG_SHOWN = 300
      EVIDENCE_SHOWN = 160
      FIX_SHOWN = 250
      NOT_CHECKED_SHOWN = 160

      # The message that opens the run's thread, redrawn in place as the run moves: what Halon looked at so far and the
      # answer as the last task. rich is whether the workspace's Slack shows plan blocks. A question with no incident is
      # named by its own words, which came from a person and are escaped where they are read as markup.
      def self.checklist(progress:, incident:, started_by:, question: nil, rich: true)
        blocks = Checklist.blocks(
          title: checklist_title(progress, incident, question), rich: rich, emoji: ":mag:",
          items: progress.tasks.map { |task| Checklist::Item.new(id: task.key, title: task.title, status: TASK_STATUSES.fetch(task.status), detail: task.detail) }
        )
        where = progress.finished? ? "Halon's work is in the thread" : "Halon is working in the thread"
        footer = [ ("Started by #{Mrkdwn.escape(started_by)}" if started_by.present?), where ].compact.join("  ·  ")
        blocks << { type: "context", elements: [ { type: "mrkdwn", text: footer } ] }
        link = open_block(progress.investigation)
        blocks << link if link
        blocks
      end

      def self.checklist_title(progress, incident, question)
        named = incident ? incident.identifier : "\"#{question.to_s.truncate(QUESTION_SHOWN)}\""
        return "Investigated #{named}" if progress.answered?
        return "Investigation of #{named} stopped" if progress.stopped?

        "Investigating #{named}"
      end

      def self.started_text(incident:, question:)
        incident ? "Investigating #{incident.identifier}" : "Investigating: #{question.to_s.truncate(200)}"
      end

      # The answer that led someone to declare this incident, so whoever joins the channel starts from it. Its full
      # reasoning follows in the thread, as it did where it was first answered.
      def self.carried_over(finding:, question: finding.investigation.question)
        intro = ":mag: *Declared from an investigation*" \
                "#{question.present? ? " into \"#{Mrkdwn.escape(question.to_s.truncate(200))}\"" : ''}. This is what it found."
        [ { type: "section", text: { type: "mrkdwn", text: intro } }, *answer(finding: finding) ]
      end

      # The short answer, posted in the thread and to the whole channel: what kind of answer it is and how sure, what is
      # wrong, up to three facts behind it, the fix, and what could not be checked, each in the plain words the agent gave
      # for a channel. The full reasoning, with the code it read, is the thread reply after it (answer_detail).
      def self.answer(finding:)
        title = [ "#{ANSWER_EMOJI.fetch(finding.shown_kind)}  *#{finding.headline}*", finding.sureness ].compact.join("  ·  ")
        lines = [ plain(finding.what_is_wrong_line, WRONG_SHOWN) ]
        lines.concat(finding.short_evidence.map { |claim| "• #{plain(claim, EVIDENCE_SHOWN)}" })
        fix = finding.suggested_fix_line
        lines << "*Suggested fix:* #{plain(fix, FIX_SHOWN)}" if fix.present?
        blocks = [
          { type: "section", text: { type: "mrkdwn", text: title } }, { type: "divider" },
          { type: "section", text: { type: "mrkdwn", text: lines.join("\n").truncate(Formatting::SECTION_TEXT_LIMIT) } }
        ]
        actions = action_block(finding)
        blocks << actions if actions
        if finding.not_checked.present?
          blocks << { type: "context", elements: [ { type: "mrkdwn", text: "_Could not check: #{plain(finding.not_checked, NOT_CHECKED_SHOWN)}_" } ] }
        end
        blocks
      end

      # What a notification or a client without blocks shows of the answer.
      def self.answer_text(finding) = "#{finding.headline}: #{finding.what_is_wrong_line}"

      # The full answer, in the thread only: the reasoning as the agent wrote it, every claim with what it rests on, the
      # fix step by step, what could not be checked and why, and the rating.
      def self.answer_detail(finding:)
        blocks = [
          { type: "section", text: { type: "mrkdwn", text: ":page_facing_up:  *The full answer*" } }, { type: "divider" },
          { type: "section", text: { type: "mrkdwn", text: summary_text(finding) } }
        ]
        blocks << evidence_block(finding) if finding.evidence_items.any?
        blocks << fix_block(finding.remediation_plan) if finding.remediation_plan
        blocks << gaps_block(finding) if finding.gaps.present?
        blocks.concat(feedback_blocks(finding))
      end

      def self.answer_detail_text(finding) = "The full answer: #{finding.summary.to_s.truncate(200)}"

      # The agent's words for a channel, escaped, on one line, with no code formatting, cut at limit.
      def self.plain(text, limit)
        Mrkdwn.escape(text.to_s.squish.delete("`").truncate(limit))
      end

      # The button is offered only when running it again could end differently.
      # What the run did before it stopped follows the reason in its own section, so responders pick up from there.
      def self.stopped(reason:, where_it_stopped: nil, rerun: nil, rerun_question: nil, investigation: nil)
        blocks = [ { type: "section", text: { type: "mrkdwn", text: ":warning: *Stopped without an answer.* #{reason}." } } ]
        blocks << { type: "section", text: { type: "mrkdwn", text: Slack::Mrkdwn.escape(where_it_stopped) } } if where_it_stopped.present?
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
        plan = finding.remediation_plan
        elements = [
          (declare_button(investigation) if finding.suggests_incident && investigation.incident.nil?),
          (apply_button(plan) if plan && plan.apply_blocked_reason.nil?),
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

      # Asks first, since the steps change things for real and run as whoever clicks.
      def self.apply_button(plan)
        runs = plan.steps.count(&:runs_itself?)
        by_hand = plan.steps.size - runs
        waits = by_hand.positive? ? " #{by_hand} #{'step'.pluralize(by_hand)} for a person #{by_hand == 1 ? 'is' : 'are'} marked done in the thread." : ""
        what = plan.undo? ? "undo" : "fix"
        {
          type: "button", style: "primary", text: { type: "plain_text", text: "Apply #{what}" },
          action_id: Identifiers::APPLY_FIX, value: plan.id,
          confirm: {
            title: { type: "plain_text", text: "Apply this #{what}?" },
            text: { type: "plain_text", text: "Runs #{runs} #{'step'.pluralize(runs)} through your connections, as you, in order.#{waits}" },
            confirm: { type: "plain_text", text: "Apply #{what}" },
            deny: { type: "plain_text", text: "Cancel" }
          }
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
        Formatting.markdown_to_mrkdwn(finding.summary.to_s).truncate(Formatting::SECTION_TEXT_LIMIT)
      end

      def self.evidence_block(finding)
        lines = finding.evidence_items.first(EVIDENCE_LIMIT).map { |item| evidence_line(item) }
        {
          type: "section",
          text: { type: "mrkdwn", text: "*Why I think so*\n#{lines.join("\n")}".truncate(Formatting::SECTION_TEXT_LIMIT) }
        }
      end

      # The claim, then what it rests on, so a reader sees where each line came from.
      def self.evidence_line(item)
        sources = item.source_labels.first(SOURCES_SHOWN).join(", ")
        line = "• #{Formatting.markdown_to_mrkdwn(item.claim)}"
        sources.present? ? "#{line} _(#{Formatting.markdown_to_mrkdwn(sources)})_" : line
      end

      # The fix in order, each step saying how it gets done and where, then how to tell it worked.
      # An undo is posted on its own once written, to apply the same way as the fix.
      def self.undo(plan:)
        blocks = [
          { type: "section", text: { type: "mrkdwn", text: ":leftwards_arrow_with_hook:  *How to undo it*" } },
          { type: "divider" },
          fix_block(plan, title: nil)
        ]
        blocks << { type: "actions", elements: [ apply_button(plan) ] } if plan.apply_blocked_reason.nil?
        blocks
      end

      # What a tool step sends, cut short, since it runs as whoever applies the fix. The run page has it whole.
      def self.sends(step)
        return "" unless step.action? && step.arguments.present?

        "\n      `#{Mrkdwn.escape(step.arguments.to_json.tr('`', "'")).truncate(ARGUMENTS_SHOWN)}`"
      end

      def self.fix_block(plan, title: "How to fix it")
        all = plan.steps.to_a
        steps = all.first(FIX_STEPS_SHOWN).map do |step|
          where = step.repository ? Mrkdwn.escape(step.repository) : (step.page_check? ? Mrkdwn.escape(step.arguments.to_h["url"].to_s) : step.action_key)
          "#{step.position}. _#{STEP_KINDS.fetch(step.kind)}#{" in `#{where}`" if where}_ #{Formatting.markdown_to_mrkdwn(Mrkdwn.escape(step.description))}#{sends(step)}"
        end
        hidden = all.size - FIX_STEPS_SHOWN
        more = hidden.positive? ? "\n#{hidden} more #{'step'.pluralize(hidden)} on the run page." : ""
        verify = plan.verify.present? ? "\n_How to tell it worked:_ #{Formatting.markdown_to_mrkdwn(Mrkdwn.escape(plan.verify))}" : ""
        text = "#{"*#{title}*\n" if title}#{Formatting.markdown_to_mrkdwn(Mrkdwn.escape(plan.summary))}\n#{steps.join("\n")}#{more}#{verify}"
        { type: "section", text: { type: "mrkdwn", text: text.truncate(Formatting::SECTION_TEXT_LIMIT) } }
      end

      def self.gaps_block(finding)
        {
          type: "context",
          elements: [ { type: "mrkdwn", text: "*Could not check:* #{finding.gaps}".truncate(Formatting::SECTION_TEXT_LIMIT) } ]
        }
      end

      RATINGS = [
        [ Identifiers::RATE_INVESTIGATION_RIGHT, Investigation::Finding::OUTCOME_CONFIRMED, "Right" ],
        [ Identifiers::RATE_INVESTIGATION_PARTLY, Investigation::Finding::OUTCOME_PARTIAL, "Partly right" ],
        [ Identifiers::RATE_INVESTIGATION_WRONG, Investigation::Finding::OUTCOME_WRONG, "Wrong" ]
      ].freeze

      # Three buttons, since Slack's own feedback element holds only two. Whoever presses one is told what they said.
      def self.feedback_blocks(finding)
        [
          { type: "context", elements: [ { type: "mrkdwn", text: "Was this answer right?" } ] },
          {
            type: "actions",
            elements: RATINGS.map do |action_id, outcome, label|
              {
                type: "button", action_id: action_id, value: "#{finding.id}:#{outcome}",
                text: { type: "plain_text", text: label },
                accessibility_label: "This answer was #{Investigation::Finding::OUTCOME_WORDS.fetch(outcome)}"
              }
            end
          }
        ]
      end
    end
  end
end
