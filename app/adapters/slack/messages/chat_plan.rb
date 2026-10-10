module Slack
  module Messages
    # A plan Halon keeps for a chat, as a checklist, redrawn in place as each step moves. It offers what its state offers:
    # Schedule and Cancel while it waits for approval, Cancel once scheduled, Retry and Undo once it stopped, Undo once it
    # finished. Slack cannot show a button as blocked, so a press someone may not make is answered privately with why. In
    # the person's direct messages it also offers to open the chat when the chat is on the dashboard.
    module ChatPlan
      TITLES = {
        ::Chat::Plan::STATUS_PROPOSED => ":calendar:", ::Chat::Plan::STATUS_SCHEDULED => ":calendar:", ::Chat::Plan::STATUS_ACTIVE => ":clipboard:",
        ::Chat::Plan::STATUS_COMPLETED => ":white_check_mark:", ::Chat::Plan::STATUS_STOPPED => ":octagonal_sign:",
        ::Chat::Plan::STATUS_CANCELLED => ":wastebasket:"
      }.freeze
      STEP_MARKS = {
        ::Chat::Plan::Step::STATUS_NOT_STARTED => ":white_circle:", ::Chat::Plan::Step::STATUS_RUNNING => ":hourglass_flowing_sand:",
        ::Chat::Plan::Step::STATUS_DONE => ":white_check_mark:", ::Chat::Plan::Step::STATUS_FAILED => ":x:",
        ::Chat::Plan::Step::STATUS_SKIPPED => ":heavy_minus_sign:"
      }.freeze
      VERDICTS = {
        ::Chat::Plan::Step::VERDICT_HELD => "worked", ::Chat::Plan::Step::VERDICT_NOT_HELD => "did not work",
        ::Chat::Plan::Step::VERDICT_UNKNOWN => "could not check"
      }.freeze
      BUTTONS = {
        ::Chat::Plan::ACTION_SCHEDULE => [ "Schedule", Identifiers::CHAT_PLAN_SCHEDULE, "primary" ],
        ::Chat::Plan::ACTION_RETRY => [ "Retry", Identifiers::CHAT_PLAN_RETRY, "primary" ],
        ::Chat::Plan::ACTION_UNDO => [ "Undo", Identifiers::CHAT_PLAN_UNDO, nil ],
        ::Chat::Plan::ACTION_CANCEL => [ "Cancel plan", Identifiers::CHAT_PLAN_CANCEL, nil ]
      }.freeze
      # The same words the dashboard's dialogs use.
      CONFIRMS = {
        ::Chat::Plan::ACTION_CANCEL => [ "Cancel this plan?", "Nothing in it will run. Halon can make a new plan when you ask.", "Cancel plan" ],
        ::Chat::Plan::ACTION_UNDO => [ "Undo this plan?", "Halon puts back what the plan changed, newest first, from the undo each change was written with. " \
                                                       "Each change still asks you before it runs.", "Undo plan" ]
      }.freeze
      NOTE_SHOWN = 300

      def self.build(plan, direct: false, conversation_id: nil)
        blocks = [
          { type: "section", text: { type: "mrkdwn", text: "#{TITLES.fetch(plan.status)}  *#{Mrkdwn.escape(plan.heading)}*" } },
          { type: "divider" },
          { type: "section", text: { type: "mrkdwn", text: "> #{Mrkdwn.escape(plan.goal)}\n#{Mrkdwn.escape(plan.progress_words)}" } },
          { type: "section", text: { type: "mrkdwn", text: steps_text(plan).truncate(Formatting::SECTION_TEXT_LIMIT) } }
        ]
        said = said_text(plan)
        blocks << { type: "section", text: { type: "mrkdwn", text: said.truncate(Formatting::SECTION_TEXT_LIMIT) } } if said.present?
        buttons = [ *plan.offers.map { |action| button(plan, action) }, (link(conversation_id) if direct) ].compact
        blocks << { type: "actions", elements: buttons } if buttons.any?
        footer = footer_text(plan)
        blocks << { type: "context", elements: [ { type: "mrkdwn", text: footer } ] } if footer.present?
        blocks
      end

      def self.fallback(plan) = "#{plan.heading}: #{plan.goal}. #{plan.progress_words}"

      def self.steps_text(plan)
        plan.steps.map do |step|
          verdict = (" · _#{VERDICTS.fetch(step.verdict)}_" if step.verdict)
          place = (" · #{Mrkdwn.escape(step.place)}" if step.place)
          tool = (" · runs #{Mrkdwn.escape(::Chat::Tools.title_for(step.tool, plan.workspace))}" if step.tool)
          line = "#{STEP_MARKS.fetch(step.status)} #{step.position}. #{Mrkdwn.escape(step.description)}#{place}#{tool}#{verdict}"
          step.note.present? ? "#{line}\n      #{Mrkdwn.escape(step.note.truncate(NOTE_SHOWN))}" : line
        end.join("\n")
      end

      # Why it stopped, which for a scheduled run is what Halon read before its time, or how it ended with its pages and
      # the next step.
      def self.said_text(plan)
        lines = []
        lines << Mrkdwn.escape(plan.stop_reason) if ::Chat::Plan::ENDED.include?(plan.status) && plan.stop_reason.present?
        if plan.completed?
          lines << Mrkdwn.escape(plan.outcome) if plan.outcome.present?
          lines.concat(plan.links.map { |url| "<#{url.delete('<>|')}|#{Mrkdwn.escape(url.sub(%r{\Ahttps?://}, '').truncate(80))}>" })
          lines << "*Next:* #{Mrkdwn.escape(plan.next_step)}" if plan.next_step.present?
        end
        lines.join("\n")
      end

      def self.footer_text(plan)
        approved = plan.approved_by && !::Chat::Plan::NOT_STARTED.include?(plan.status)
        [ ("Undoes: #{Mrkdwn.escape(plan.undoes.goal)}" if plan.undoes), ("Approved by #{Mrkdwn.escape(plan.approved_by.display_name)}" if approved) ]
          .compact.join("  ·  ")
      end

      def self.button(plan, action)
        text, action_id, style = BUTTONS.fetch(action)
        element = { type: "button", text: { type: "plain_text", text: text }, action_id: action_id, value: plan.id, style: style }.compact
        title, words, confirm = CONFIRMS[action]
        return element unless title

        element.merge(confirm: {
          title: { type: "plain_text", text: title }, text: { type: "plain_text", text: words },
          confirm: { type: "plain_text", text: confirm }, deny: { type: "plain_text", text: "Keep it" }
        })
      end

      def self.link(conversation_id)
        url = conversation_id && DashboardUrl.agent_chat(conversation_id)
        return unless url

        { type: "button", text: { type: "plain_text", text: "Open the chat" }, url: url }
      end
    end
  end
end
