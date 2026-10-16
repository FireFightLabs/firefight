module Slack
  module Messages
    # A request for an approver, by direct message or in a channel. A call is asked as a card saying in plain words who
    # wants to do what (ApprovalNotificationService::Shown), who may approve it, and Approve, Deny and Details, with the
    # call's key, scope and parameters under Details (Modals::ApprovalDetails). A workflow's Approval step asks its
    # question instead. Once decided the same message says by whom, and once the call it let through ran, how it went.
    module Approval
      REQUEST_ICON = ":raised_hand:".freeze
      APPROVE = "Approve".freeze
      DENY = "Deny".freeze
      DETAILS = "Details".freeze
      LINK_TEXT_LIMIT = 60

      def self.build_request(approval, shown:, rich: false)
        return question_request(approval, rich: rich) if approval.workflow_question?

        actions = [ *decision_buttons(approval), details_button(approval) ]
        Blocks::Card.new(icon: REQUEST_ICON, title: Mrkdwn.escape(wants(shown)), body: request_line(approval), actions: actions).to_blocks(rich: rich)
      end

      # A workflow's Approval step: what it asks and what approvers should know, rather than a call.
      def self.question_request(approval, rich:)
        title = "#{Mrkdwn.escape(approval.principal_label)} asks: #{Mrkdwn.escape(approval.question.to_s)}"
        card = Blocks::Card.new(icon: REQUEST_ICON, title: title, body: approvers_line(approval), actions: decision_buttons(approval)).to_blocks(rich: rich)
        return card if approval.question_details.blank?

        card + [ { type: "section", text: { type: "mrkdwn", text: CodeQuestion.quoted(approval.question_details).truncate(Formatting::SECTION_TEXT_LIMIT) } } ]
      end

      # Approved or denied says by whom, and an approved call says how it went once it ran. Withdrawn, the buttons are gone
      # and it says why, after whoever approved it when it was approved but never ran.
      def self.build_resolved(approval, shown:, rich: false)
        title = approval.workflow_question? ? "#{Mrkdwn.escape(approval.principal_label)} asked: #{Mrkdwn.escape(approval.question.to_s)}" : Mrkdwn.escape(wants(shown))
        actions = approval.workflow_question? ? [] : [ details_button(approval) ]
        Blocks::Card.new(icon: resolved_icon(approval, shown), title: title, body: verdict(approval, shown), actions: actions).to_blocks(rich: rich)
      end

      def self.wants(shown) = "#{shown.who} wants to: #{shown.action}"

      def self.resolved_icon(approval, shown)
        return ":hourglass:" if approval.expired?
        return ":no_entry_sign:" unless approval.approved?

        { ApprovalNotificationService::OUTCOME_FAILED => ":x:", ApprovalNotificationService::OUTCOME_WORKING => ":arrows_counterclockwise:" }
          .fetch(shown.outcome, ":white_check_mark:")
      end

      def self.verdict(approval, shown)
        return withdrawn_text(approval) if approval.expired?

        by = "*#{Mrkdwn.escape(approval.approver&.actor_display_name.to_s)}*"
        return "Denied by #{by}" unless approval.approved?

        case shown.outcome
        when ApprovalNotificationService::OUTCOME_WORKING then "Approved by #{by}  ·  working…"
        when ApprovalNotificationService::OUTCOME_DONE then [ "Approved by #{by}", "Done", link(shown.link) ].compact.join("  ·  ")
        when ApprovalNotificationService::OUTCOME_FAILED then "Approved by #{by}  ·  Failed: #{Mrkdwn.escape(Chat::Tools.plain(shown.reason.presence || 'it did not go through', 150))}"
        else "Approved by #{by}"
        end
      end

      def self.withdrawn_text(approval)
        why = Mrkdwn.escape(approval.withdrawn_reason.presence || "It is no longer needed, so nothing will run.")
        approved = " after *#{Mrkdwn.escape(approval.approver.actor_display_name)}* approved it" if approval.approver
        "Withdrawn#{approved}. #{why}"
      end

      def self.link(url)
        return if url.blank?

        "<#{url}|#{Mrkdwn.escape(url.sub(%r{\Ahttps?://}, '').delete_suffix('/').truncate(LINK_TEXT_LIMIT))}>"
      end

      # The same words the blocks say. An approval that expired here was withdrawn, since nothing needs it any more.
      def self.resolved_fallback(approval, shown:)
        state = if approval.expired? then "withdrawn"
        elsif approval.approved? then { ApprovalNotificationService::OUTCOME_DONE => "done", ApprovalNotificationService::OUTCOME_FAILED => "failed" }.fetch(shown.outcome, "approved")
        else approval.status
        end
        "#{approval.workflow_question? ? approval.question : wants(shown)}: #{state}"
      end

      def self.request_fallback(approval, shown:)
        return "#{approval.principal_label} asks: #{approval.question}" if approval.workflow_question?

        wants(shown)
      end

      # Where it runs, when it runs through a connection, and who may approve it.
      def self.request_line(approval)
        through = ("Through *#{Mrkdwn.escape(approval.connection_name)}*" if approval.connection_name)
        [ through, approvers_line(approval) ].compact.join("  ·  ")
      end

      def self.decision_buttons(approval)
        [
          { type: "button", style: "primary", action_id: Identifiers::APPROVE_ABILITY, text: { type: "plain_text", text: APPROVE }, value: approval.id },
          { type: "button", style: "danger", action_id: Identifiers::DENY_ABILITY, text: { type: "plain_text", text: DENY }, value: approval.id }
        ]
      end

      def self.details_button(approval)
        { type: "button", action_id: Identifiers::APPROVAL_DETAILS, text: { type: "plain_text", text: DETAILS }, value: approval.id }
      end

      def self.approvers_line(approval)
        on_call = " or whoever is on call for #{approval.incident.identifier}" if approval.on_call_may_approve? && approval.incident
        return "Needs a workspace #{approval.required_role}#{on_call}" unless approval.named_approvers?

        mentions = approval.approvers.map do |approver|
          approver.actor_kind == Ability::Principal::KIND_USER ? Slack::Mrkdwn.mention(approver) : "*#{Slack::Mrkdwn.escape(approver.actor_display_name)}* (agent)"
        end
        "Approvers: #{mentions.join(', ')}#{on_call}"
      end
    end
  end
end
