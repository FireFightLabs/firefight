module Slack
  module Messages
    # A run's fix as it is applied, in its thread, redrawn as each step moves. A step a person does carries Mark done.
    module FixProgress
      RESULT_SHOWN = 300
      # Slack takes 50 blocks. The steps share this many, an approved one taking three, and the rest of the room is kept for
      # the heading, the count of steps left out, Undo and Cancel. A long fix sends what does not fit to the run page.
      STEP_BLOCKS = 45
      HEADINGS = {
        Investigation::RemediationPlan::STATUS_PROPOSED => "Fix in progress",
        Investigation::RemediationPlan::STATUS_APPLYING => "Applying the fix",
        Investigation::RemediationPlan::STATUS_APPLIED => "Fix applied",
        Investigation::RemediationPlan::STATUS_PARTLY_APPLIED => "Fix partly applied",
        Investigation::RemediationPlan::STATUS_CANCELLED => "Fix cancelled"
      }.freeze
      UNDO_HEADINGS = {
        Investigation::RemediationPlan::STATUS_PROPOSED => "Undo in progress",
        Investigation::RemediationPlan::STATUS_APPLYING => "Undoing the fix",
        Investigation::RemediationPlan::STATUS_APPLIED => "Fix undone",
        Investigation::RemediationPlan::STATUS_PARTLY_APPLIED => "Fix partly undone",
        Investigation::RemediationPlan::STATUS_CANCELLED => "Undo cancelled"
      }.freeze
      def self.build(plan)
        steps = plan.steps.includes(:done_by, approval: :approver).to_a
        blocks = [ { type: "section", text: { type: "mrkdwn", text: heading(plan, steps) } } ]
        shown = 0
        steps.each do |step|
          rows = step_blocks(step, steps)
          break if blocks.size - 1 + rows.size > STEP_BLOCKS

          blocks.concat(rows)
          shown += 1
        end
        hidden = steps.size - shown
        blocks << { type: "context", elements: [ { type: "mrkdwn", text: "#{hidden} more #{'step'.pluralize(hidden)} on the run page." } ] } if hidden.positive?
        blocks << undo_block(plan) if plan.undo_blocked_reason.nil?
        blocks << cancel_block(plan) if plan.cancel_blocked_reason.nil?
        blocks
      end

      # The same words the run page's dialog uses.
      def self.cancel_text(plan)
        said = "Steps that have not run never will, and approvals they wait on are withdrawn. A step already running finishes"
        plan.undo? ? "#{said}." : "#{said}, and whatever went through can be undone."
      end

      # Stops what has not run yet. A step already running finishes, which the confirm says.
      def self.cancel_block(plan)
        what = plan.undo? ? "undo" : "fix"
        {
          type: "actions",
          elements: [ {
            type: "button", style: "danger", text: { type: "plain_text", text: "Cancel #{what}" }, action_id: Identifiers::CANCEL_FIX, value: plan.id,
            confirm: {
              title: { type: "plain_text", text: "Cancel this #{what}?" },
              text: { type: "plain_text", text: cancel_text(plan) },
              confirm: { type: "plain_text", text: "Cancel #{what}" }, deny: { type: "plain_text", text: "Keep going" }
            }
          } ]
        }
      end

      # Halon writes the undo when asked, and a person applies it like the fix, so asking changes nothing yet.
      def self.undo_block(plan)
        {
          type: "actions",
          elements: [ {
            type: "button", text: { type: "plain_text", text: "Undo fix" }, action_id: Identifiers::UNDO_FIX, value: plan.id,
            confirm: {
              title: { type: "plain_text", text: "Write the undo?" },
              text: { type: "plain_text", text: "Halon writes the steps that put back what this fix changed. Nothing changes until someone applies them." },
              confirm: { type: "plain_text", text: "Write the undo" }, deny: { type: "plain_text", text: "Cancel" }
            }
          } ]
        }
      end

      def self.headings(plan) = plan.undo? ? UNDO_HEADINGS : HEADINGS

      def self.fallback(plan)
        "#{headings(plan).fetch(plan.status)}: #{plan.steps.count(&:done?)} of #{plan.steps.size} steps done"
      end

      def self.heading(plan, steps)
        name = plan.cancelled? ? plan.cancelled_by&.display_name : plan.applier_name
        by = name ? " by #{Mrkdwn.escape(name)}" : ""
        "*#{headings(plan).fetch(plan.status)}*#{by}. #{steps.count(&:done?)} of #{steps.size} steps done."
      end

      # An approved step asks to be run, with how things stand now, and carries Run and Dismiss, or Ask again once its
      # approval expired. Approving it never ran it.
      def self.step_blocks(step, steps)
        block = { type: "section", text: { type: "mrkdwn", text: step_text(step).truncate(Formatting::SECTION_TEXT_LIMIT) } }
        if step.mark_done_blocked_reason(steps).nil?
          block[:accessory] = { type: "button", text: { type: "plain_text", text: "Mark done" }, action_id: Identifiers::MARK_FIX_STEP_DONE, value: step.id }
        end
        return [ block ] unless step.approved?

        [ block, { type: "context", elements: [ { type: "mrkdwn", text: approved_text(step).truncate(Formatting::SECTION_TEXT_LIMIT) } ] }, approved_actions(step) ]
      end

      def self.approved_text(step)
        approver = Mrkdwn.escape(step.approval&.approver&.actor_display_name || "An approver")
        return "#{approver} approved it, but nobody ran it within the hour, so the approval expired." if step.lapsed?
        return "#{approver} approved it. Halon is checking how things stand now, and Run waits until it has." if step.checking?

        report = step.report
        lines = [ "#{approver} approved it. Run it now?" ]
        lines << "*Now:* #{Mrkdwn.escape(report.state)}" if report&.state
        lines << ":warning: #{Mrkdwn.escape(report.warning)}" if report&.warning
        expires = step.approval&.run_expires_at
        lines << "Expires #{Formatting.slack_time(expires)}" if expires
        lines.join("\n")
      end

      STEP_BUTTONS = {
        Chat::CurrentState::ACTION_RUN => [ "Run", Identifiers::FIX_STEP_RUN, "primary" ],
        Chat::CurrentState::ACTION_DISMISS => [ "Dismiss", Identifiers::FIX_STEP_DISMISS, nil ],
        Chat::CurrentState::ACTION_ASK_AGAIN => [ "Ask again", Identifiers::FIX_STEP_ASK_AGAIN, nil ]
      }.freeze

      # Slack cannot show a button as blocked, so Run joins once Halon has checked, when the message is redrawn.
      def self.approved_actions(step)
        offers = step.offers
        offers -= [ Chat::CurrentState::ACTION_RUN ] if step.checking?
        elements = offers.map do |offer|
          text, action_id, style = STEP_BUTTONS.fetch(offer)
          { type: "button", text: { type: "plain_text", text: text }, action_id: action_id, value: step.id, style: style }.compact
        end
        { type: "actions", elements: elements }
      end

      STEP_NEWS_TITLES = {
        Investigation::RemediationStep::STATUS_APPROVED => ":unlock:", Investigation::RemediationStep::STATUS_DECLINED => ":no_entry_sign:"
      }.freeze

      # To whoever applied a fix that has no thread, when one of its steps was decided on.
      def self.step_news(step)
        blocks = [ { type: "section", text: { type: "mrkdwn", text: "#{STEP_NEWS_TITLES.fetch(step.status, ':hourglass:')}  *#{Mrkdwn.escape(step_news_fallback(step))}*" } },
                   { type: "divider" },
                   { type: "section", text: { type: "mrkdwn", text: step_text(step).truncate(Formatting::SECTION_TEXT_LIMIT) } } ]
        url = DashboardUrl.investigation(step.plan.finding.investigation)
        blocks << { type: "actions", elements: [ { type: "button", text: { type: "plain_text", text: "Open the run" }, url: url } ] } if url
        blocks
      end

      def self.step_news_fallback(step)
        approver = step.approval&.approver&.actor_display_name || "An approver"
        return "#{approver} declined step #{step.position} of the fix. It did not run." unless step.approved?
        return "The approval for step #{step.position} of the fix expired before anyone ran it." if step.lapsed?

        "#{approver} approved step #{step.position} of the fix. Run it now?"
      end

      # A tool's result is another system's words, so it is escaped and cut short. The run page has it whole. While a
      # coding agent works on the step, where it has got to stands in for the result, the latest thing it did and the
      # counts, never every line.
      def self.step_text(step)
        status = step.status_label
        status = status ? "\n_#{Mrkdwn.escape(status)}_" : ""
        said = step.status == Investigation::RemediationStep::STATUS_RUNNING && step.work ? step.work.headline : step.result
        result = said.present? ? "\n>#{Mrkdwn.escape(said.truncate(RESULT_SHOWN)).gsub("\n", "\n>")}" : ""
        "*#{step.position}.* #{Formatting.markdown_to_mrkdwn(Mrkdwn.escape(step.description))}#{status}#{result}"
      end
    end
  end
end
