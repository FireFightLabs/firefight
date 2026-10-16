module Slack
  module Modals
    # The call an approval request is for, as the gateway holds it, which its card keeps off it: the action, where it
    # runs, the scope and the parameters. params is what the request asks with as people read it.
    module ApprovalDetails
      def self.build(approval, params:)
        texts = [
          "*Action*\n#{Mrkdwn.escape(approval.action_key)}",
          ("*Through*\n#{Mrkdwn.escape(approval.connection_name)}" if approval.connection_name),
          ("*Scope*\n```#{Mrkdwn.escape(JSON.pretty_generate(approval.scope))}```" if approval.scope.present?),
          ("*Parameters*\n```#{Mrkdwn.escape(JSON.pretty_generate(params))}```" if params.present?),
          "*Asked by*\n#{Mrkdwn.escape(approval.principal_label)}"
        ].compact
        {
          type: "modal", title: { type: "plain_text", text: "Details" }, close: { type: "plain_text", text: "Close" },
          blocks: texts.map { |text| { type: "section", text: { type: "mrkdwn", text: text.truncate(Messages::Formatting::SECTION_TEXT_LIMIT) } } }
        }
      end
    end
  end
end
