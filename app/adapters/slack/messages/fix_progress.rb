module Slack
  module Messages
    # A run's fix as it is applied, in its thread, redrawn as each step moves. A step a person does carries Mark done.
    module FixProgress
      SECTION_TEXT_LIMIT = 3000
      RESULT_SHOWN = 300
      # Slack takes 50 blocks, so a long fix shows its first steps and sends the rest to the run page.
      STEPS_SHOWN = 45
      HEADINGS = {
        Investigation::RemediationPlan::STATUS_PROPOSED => "Fix in progress",
        Investigation::RemediationPlan::STATUS_APPLYING => "Applying the fix",
        Investigation::RemediationPlan::STATUS_APPLIED => "Fix applied",
        Investigation::RemediationPlan::STATUS_PARTLY_APPLIED => "Fix partly applied"
      }.freeze
      STATUSES = {
        Investigation::RemediationStep::STATUS_PROPOSED => "Not started",
        Investigation::RemediationStep::STATUS_RUNNING => "Running",
        Investigation::RemediationStep::STATUS_WAITING_APPROVAL => "Waiting for approval",
        Investigation::RemediationStep::STATUS_DONE => "Done",
        Investigation::RemediationStep::STATUS_FAILED => "Failed",
        Investigation::RemediationStep::STATUS_DECLINED => "Declined",
        Investigation::RemediationStep::STATUS_SKIPPED => "Skipped, since a step it waits on did not go through"
      }.freeze

      def self.build(plan)
        steps = plan.steps.includes(:done_by).to_a
        blocks = [ { type: "section", text: { type: "mrkdwn", text: heading(plan, steps) } }, *steps.first(STEPS_SHOWN).map { |step| step_block(step, steps) } ]
        hidden = steps.size - STEPS_SHOWN
        blocks << { type: "context", elements: [ { type: "mrkdwn", text: "#{hidden} more #{'step'.pluralize(hidden)} on the run page." } ] } if hidden.positive?
        blocks
      end

      def self.fallback(plan)
        "#{HEADINGS.fetch(plan.status)}: #{plan.steps.count(&:done?)} of #{plan.steps.size} steps done"
      end

      def self.heading(plan, steps)
        by = plan.approved_by ? " by #{Mrkdwn.escape(plan.approved_by.display_name)}" : ""
        "*#{HEADINGS.fetch(plan.status)}*#{by}. #{steps.count(&:done?)} of #{steps.size} steps done."
      end

      def self.step_block(step, steps)
        block = { type: "section", text: { type: "mrkdwn", text: step_text(step).truncate(SECTION_TEXT_LIMIT) } }
        if step.mark_done_blocked_reason(steps).nil?
          block[:accessory] = { type: "button", text: { type: "plain_text", text: "Mark done" }, action_id: Identifiers::MARK_FIX_STEP_DONE, value: step.id }
        end
        block
      end

      # A tool's result is another system's words, so it is escaped and cut short. The run page has it whole.
      def self.step_text(step)
        status = STATUSES.fetch(step.status)
        status = "Done by #{Mrkdwn.escape(step.done_by.display_name)}" if step.done? && step.done_by
        result = step.result.present? ? "\n>#{Mrkdwn.escape(step.result.truncate(RESULT_SHOWN)).gsub("\n", "\n>")}" : ""
        "*#{step.position}.* #{Formatting.markdown_to_mrkdwn(Mrkdwn.escape(step.description))}\n_#{status}_#{result}"
      end
    end
  end
end
