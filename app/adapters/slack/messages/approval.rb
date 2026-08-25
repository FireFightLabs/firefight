module Slack
  module Messages
    module Approval
      def self.build_request(approval)
        [
          { type: "header", text: { type: "plain_text", text: ":lock: Approval required", emoji: true } },
          { type: "section", text: { type: "mrkdwn", text: summary_text(approval) } },
          { type: "actions", elements: [
            { type: "button", style: "primary", action_id: Identifiers::APPROVE_ABILITY,
              text: { type: "plain_text", text: "Approve" }, value: approval.id },
            { type: "button", style: "danger", action_id: Identifiers::DENY_ABILITY,
              text: { type: "plain_text", text: "Deny" }, value: approval.id }
          ] }
        ]
      end

      def self.build_resolved(approval)
        verdict = approval.approved? ? ":white_check_mark: *Approved*" : ":no_entry: *Denied*"
        [
          { type: "header", text: { type: "plain_text", text: ":lock: Approval request", emoji: true } },
          { type: "section", text: { type: "mrkdwn", text: summary_text(approval) } },
          { type: "section", text: { type: "mrkdwn", text: "#{verdict} by *#{approval.approver&.actor_display_name}*" } }
        ]
      end

      def self.summary_text(approval)
        lines = [ "*#{approval.principal_label}* wants to run `#{approval.action_key}`" ]
        lines << "*Scope:* `#{approval.scope.to_json}`" if approval.scope.present?
        lines << "*Params:* `#{approval.params.to_json.truncate(500)}`" if approval.params.present?
        lines << approvers_line(approval)
        lines.join("\n")
      end

      def self.approvers_line(approval)
        return "*Requires:* workspace #{approval.required_role}" unless approval.named_approvers?

        mentions = approval.approvers.map do |approver|
          approver.platform_user_id ? "<@#{approver.platform_user_id}>" : "*#{approver.actor_display_name}* (agent)"
        end
        "*Approvers:* #{mentions.join(', ')}"
      end
    end
  end
end
