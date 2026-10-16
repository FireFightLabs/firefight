module Slack
  module Messages
    # A run's fix as it is applied, in its thread and the channel, redrawn as each step moves: a checklist with each step
    # by its short name and how it stands, then what a person can do now. A step a person does carries Mark done, an
    # approved one Run and Dismiss, and a failed one Try again. The steps' full instructions are in the answer's thread
    # reply and on the run page.
    module FixProgress
      RESULT_SHOWN = 300
      # Slack takes 50 blocks. The checklist is one, a step a person can act on takes up to three, and the rest of the
      # room is kept for the footer, the count of steps left out and the buttons.
      STEP_BLOCKS = 45
      HEADINGS = {
        Investigation::RemediationPlan::STATUS_PROPOSED => "Fix in progress",
        Investigation::RemediationPlan::STATUS_APPLYING => "Applying the fix",
        Investigation::RemediationPlan::STATUS_APPLIED => "Fix applied",
        Investigation::RemediationPlan::STATUS_CANCELLED => "Fix cancelled"
      }.freeze
      UNDO_HEADINGS = {
        Investigation::RemediationPlan::STATUS_PROPOSED => "Undo in progress",
        Investigation::RemediationPlan::STATUS_APPLYING => "Undoing the fix",
        Investigation::RemediationPlan::STATUS_APPLIED => "Fix undone",
        Investigation::RemediationPlan::STATUS_CANCELLED => "Undo cancelled"
      }.freeze
      ENDED_EMOJI = {
        Investigation::RemediationPlan::STATUS_APPLIED => ":white_check_mark:", Investigation::RemediationPlan::STATUS_PARTLY_APPLIED => ":warning:",
        Investigation::RemediationPlan::STATUS_CANCELLED => ":no_entry_sign:"
      }.freeze
      STOPPED = [ Investigation::RemediationStep::STATUS_FAILED, Investigation::RemediationStep::STATUS_DECLINED ].freeze

      def self.build(plan, rich: true)
        steps = plan.steps.includes(:done_by, approval: :approver).to_a
        blocks = Checklist.blocks(title: heading(plan, steps), items: steps.map { |step| item(step) }, rich: rich, emoji: ":hammer_and_wrench:")
        acting = steps.select { |step| acts_on?(step, steps) }
        shown = 0
        acting.each do |step|
          rows = step_blocks(step, steps, plan)
          break if blocks.size + rows.size > STEP_BLOCKS

          blocks.concat(rows)
          shown += 1
        end
        hidden = acting.size - shown
        blocks << { type: "context", elements: [ { type: "mrkdwn", text: footer(plan, steps, hidden) } ] }
        controls = [ (undo_button(plan) if plan.undo_blocked_reason.nil?), (cancel_button(plan) if plan.cancel_blocked_reason.nil?),
                     InvestigationRun.open_button(plan.finding.investigation) ].compact
        blocks << { type: "actions", elements: controls } if controls.any?
        blocks
      end

      CHECKLIST_STATUSES = {
        Investigation::RemediationStep::STATUS_PROPOSED => Checklist::PENDING, Investigation::RemediationStep::STATUS_SKIPPED => Checklist::PENDING,
        Investigation::RemediationStep::STATUS_RUNNING => Checklist::IN_PROGRESS,
        Investigation::RemediationStep::STATUS_WAITING_APPROVAL => Checklist::IN_PROGRESS,
        Investigation::RemediationStep::STATUS_APPROVED => Checklist::IN_PROGRESS, Investigation::RemediationStep::STATUS_DONE => Checklist::COMPLETE,
        Investigation::RemediationStep::STATUS_FAILED => Checklist::ERROR, Investigation::RemediationStep::STATUS_DECLINED => Checklist::ERROR
      }.freeze

      # A step by its short name, never the instructions the agent wrote for it, with how it stands in plain words. A
      # skipped step says why in Firefight's own words. A coding agent at work says how far it got in counts, since its
      # latest line names files and commands.
      def self.item(step)
        detail = case step.status
        when *STOPPED then step.failure_line
        when Investigation::RemediationStep::STATUS_SKIPPED then step.result.presence || step.status_label
        when Investigation::RemediationStep::STATUS_RUNNING then step.work&.counts_line
        when Investigation::RemediationStep::STATUS_DONE then (step.status_label if step.done_by)
        else step.status_label
        end
        Checklist::Item.new(id: step.id, title: "#{step.position}. #{step.shown_title}", status: CHECKLIST_STATUSES.fetch(step.status), detail: detail)
      end

      # A step someone can do something with now: mark it done, run or dismiss it once approved, or try it again.
      def self.acts_on?(step, steps)
        step.mark_done_blocked_reason(steps).nil? || step.approved? || step.retry_offered?
      end

      # An approved step asks to be run, with how things stand now, and carries Run and Dismiss, or Ask again once its
      # approval expired. Approving it never ran it.
      def self.step_blocks(step, steps, plan)
        return [ retry_block(step, plan) ] if step.retry_offered?

        name = "*#{step.position}.* #{Mrkdwn.escape(step.shown_title)}"
        block = { type: "section", text: { type: "mrkdwn", text: name } }
        if step.mark_done_blocked_reason(steps).nil?
          block[:accessory] = { type: "button", text: { type: "plain_text", text: "Mark done" }, action_id: Identifiers::MARK_FIX_STEP_DONE, value: step.id }
        end
        return [ block ] unless step.approved?

        [ block, { type: "context", elements: [ { type: "mrkdwn", text: approved_text(step).truncate(Formatting::SECTION_TEXT_LIMIT) } ] }, approved_actions(step) ]
      end

      # Runs the step again as whoever applied the fix, so it asks first, saying so.
      def self.retry_block(step, plan)
        runs_as = plan.applier_name || "whoever applied the #{plan.undo? ? 'undo' : 'fix'}"
        {
          type: "section", text: { type: "mrkdwn", text: "*#{step.position}.* #{Mrkdwn.escape(step.shown_title)}" },
          accessory: {
            type: "button", text: { type: "plain_text", text: "Try again" }, action_id: Identifiers::FIX_STEP_RETRY, value: step.id,
            confirm: {
              title: { type: "plain_text", text: "Try step #{step.position} again?" },
              text: { type: "plain_text", text: "It runs again as #{runs_as}, and the steps waiting on it go on once it is done." },
              confirm: { type: "plain_text", text: "Try again" }, deny: { type: "plain_text", text: "Cancel" }
            }
          }
        }
      end

      def self.footer(plan, steps, hidden)
        name = plan.cancelled? ? plan.cancelled_by&.display_name : plan.applier_name
        parts = [ ("#{plan.cancelled? ? 'Cancelled' : 'Applied'} by #{Mrkdwn.escape(name)}" if name),
                  "#{steps.count(&:done?)} of #{steps.size} steps done",
                  ("#{hidden} more #{'step'.pluralize(hidden)} to act on, on the run page" if hidden.positive?) ]
        parts.compact.join("  ·  ")
      end

      # Said once each time the fix ends, in the thread and the channel: applied, stopped with what failed and why, or
      # cancelled.
      def self.ended(plan)
        steps = plan.steps.to_a
        stopped = steps.select { |step| STOPPED.include?(step.status) }
        body = if plan.status == Investigation::RemediationPlan::STATUS_PARTLY_APPLIED
          [ *stopped.map { |step| Mrkdwn.escape(step.failure_line) }, ("Try again from the fix's checklist." if stopped.any?(&:failed?)) ].compact
        else
          [ "#{steps.count(&:done?)} of #{steps.size} steps done." ]
        end
        [
          { type: "section", text: { type: "mrkdwn", text: "#{ENDED_EMOJI.fetch(plan.status)}  *#{heading(plan, steps)}*" } },
          { type: "divider" },
          { type: "section", text: { type: "mrkdwn", text: body.join("\n").truncate(Formatting::SECTION_TEXT_LIMIT) } },
          { type: "context", elements: [ { type: "mrkdwn", text: footer(plan, steps, 0) } ] }
        ]
      end

      def self.ended_text(plan) = "#{heading(plan, plan.steps.to_a)}."

      # The same words the run page's dialog uses.
      def self.cancel_text(plan)
        said = "Steps that have not run never will, and approvals they wait on are withdrawn. A step already running finishes"
        plan.undo? ? "#{said}." : "#{said}, and whatever went through can be undone."
      end

      # Stops what has not run yet. A step already running finishes, which the confirm says.
      def self.cancel_button(plan)
        what = plan.undo? ? "undo" : "fix"
        {
          type: "button", style: "danger", text: { type: "plain_text", text: "Cancel #{what}" }, action_id: Identifiers::CANCEL_FIX, value: plan.id,
          confirm: {
            title: { type: "plain_text", text: "Cancel this #{what}?" },
            text: { type: "plain_text", text: cancel_text(plan) },
            confirm: { type: "plain_text", text: "Cancel #{what}" }, deny: { type: "plain_text", text: "Keep going" }
          }
        }
      end

      # Halon writes the undo when asked, and a person applies it like the fix, so asking changes nothing yet.
      def self.undo_button(plan)
        {
          type: "button", text: { type: "plain_text", text: "Undo fix" }, action_id: Identifiers::UNDO_FIX, value: plan.id,
          confirm: {
            title: { type: "plain_text", text: "Write the undo?" },
            text: { type: "plain_text", text: "Halon writes the steps that put back what this fix changed. Nothing changes until someone applies them." },
            confirm: { type: "plain_text", text: "Write the undo" }, deny: { type: "plain_text", text: "Cancel" }
          }
        }
      end

      def self.headings(plan) = plan.undo? ? UNDO_HEADINGS : HEADINGS

      def self.fallback(plan)
        "#{heading(plan, plan.steps.to_a)}: #{plan.steps.count(&:done?)} of #{plan.steps.size} steps done"
      end

      # A fix that stopped partway says how many steps failed, or did not run when none failed and some were declined,
      # dismissed or held back.
      def self.heading(plan, steps)
        return headings(plan).fetch(plan.status) unless plan.status == Investigation::RemediationPlan::STATUS_PARTLY_APPLIED

        failed = steps.count { |step| STOPPED.include?(step.status) }
        what = failed.positive? ? "#{failed} of #{steps.size} steps failed" : "#{steps.count { |step| !step.done? }} of #{steps.size} steps did not run"
        "#{plan.undo? ? 'Undo' : 'Fix'} stopped: #{what}"
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
