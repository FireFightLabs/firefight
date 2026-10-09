module Slack
  module Messages
    # A pull request Halon opened that needs attention: it conflicts with its base, a check failed or a reviewer asked
    # for changes. The body says why and what Fix it does, and Fix it runs the code change on its branch as whoever asked
    # for it. Once pressed, or once a later read moved on, it is redrawn without the button. In the asker's direct
    # messages it also offers to open the chat on the dashboard.
    module PullRequestNotice
      TITLES = {
        CodeAgentSession::Notice::STATUS_OFFERED => ":warning:", CodeAgentSession::Notice::STATUS_FIXING => ":hammer_and_wrench:",
        CodeAgentSession::Notice::STATUS_CLEARED => ":white_check_mark:", CodeAgentSession::Notice::STATUS_REPLACED => ":leftwards_arrow_with_hook:",
        CodeAgentSession::Notice::STATUS_ENDED => ":leftwards_arrow_with_hook:"
      }.freeze
      FOOTERS = {
        CodeAgentSession::Notice::STATUS_CLEARED => "The code host no longer shows this.",
        CodeAgentSession::Notice::STATUS_REPLACED => "Something newer about this pull request is below.",
        CodeAgentSession::Notice::STATUS_ENDED => "The pull request was merged or closed, so Halon stopped following it."
      }.freeze

      def self.build(notice, conversation_id: nil)
        blocks = [
          { type: "section", text: { type: "mrkdwn", text: "#{TITLES.fetch(notice.status, ':warning:')}  *#{Mrkdwn.escape(notice.headline)}*" } },
          { type: "divider" },
          { type: "section", text: { type: "mrkdwn", text: body(notice).truncate(Formatting::SECTION_TEXT_LIMIT) } }
        ]
        footer = footer(notice)
        blocks << { type: "context", elements: [ { type: "mrkdwn", text: footer } ] } if footer
        buttons = buttons(notice, conversation_id)
        blocks << { type: "actions", elements: buttons } if buttons.any?
        blocks
      end

      def self.fallback(notice) = notice.reason

      def self.body(notice)
        lines = [ Mrkdwn.escape(notice.why) ]
        lines << Mrkdwn.escape(notice.offer) if notice.offered?
        lines << "<#{notice.session.pull_request_url}|Open the pull request>" if notice.session.pull_request_url.present?
        lines.join("\n")
      end

      def self.footer(notice)
        return "Fix it pressed by #{Mrkdwn.escape(notice.fix_by&.display_name || 'someone')}. Halon says how it went in the chat." if notice.status == CodeAgentSession::Notice::STATUS_FIXING

        FOOTERS[notice.status]
      end

      def self.buttons(notice, conversation_id)
        elements = []
        if notice.offered?
          elements << { type: "button", text: { type: "plain_text", text: "Fix it" }, action_id: Identifiers::PULL_REQUEST_FIX, value: notice.id, style: "primary" }
        end
        url = conversation_id && DashboardUrl.agent_chat(conversation_id)
        elements << { type: "button", text: { type: "plain_text", text: "Open the chat" }, url: url } if url
        elements
      end
    end
  end
end
