module Slack
  module Messages
    # A code change that reached its spending limit before it finished, asking whether to continue, with Continue and
    # Stop. Only the person the change runs as can decide. Once decided it says who decided and how, and the buttons are gone.
    module CodePause
      def self.build(pause)
        blocks = [
          { type: "section", text: { type: "mrkdwn", text: ":double_vertical_bar:  *#{Mrkdwn.escape(title(pause))}*" } },
          { type: "divider" },
          { type: "section", text: { type: "mrkdwn", text: Mrkdwn.escape(CodeAgentSession::Pause::QUESTION) } }
        ]
        if pause.saved_branch && !pause.stopped?
          blocks << { type: "context", elements: [ { type: "mrkdwn", text: "Its work so far is saved on `#{Mrkdwn.escape(pause.saved_branch)}`." } ] }
        end
        return blocks << { type: "context", elements: [ { type: "mrkdwn", text: decided(pause) } ] } unless pause.offered?

        blocks << { type: "actions", elements: [
          { type: "button", text: { type: "plain_text", text: "Continue" }, action_id: Identifiers::CODE_PAUSE_CONTINUE, value: pause.id, style: "primary" },
          { type: "button", text: { type: "plain_text", text: "Stop" }, action_id: Identifiers::CODE_PAUSE_STOP, value: pause.id }
        ] }
        asker = pause.session.principal
        who = asker ? Mrkdwn.mention(asker) : "the person who asked for the change"
        blocks << { type: "context", elements: [ { type: "mrkdwn", text: "Only #{who} can decide." } ] }
      end

      def self.fallback(pause) = "#{title(pause)}: #{CodeAgentSession::Pause::QUESTION}"

      def self.title(pause) = "Code change in #{pause.repository} paused"

      def self.decided(pause)
        who = Mrkdwn.escape(pause.decided_by&.display_name || "Someone")
        pause.continuing? ? "*#{who}* chose Continue." : "*#{who}* chose Stop#{', so the saved work was deleted' if pause.saved_branch}."
      end
    end
  end
end
