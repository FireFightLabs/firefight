module Slack
  module Messages
    # A member asking an admin, by direct message, for a pack they were refused a change for. Give pack grants it
    # through the same grant as the Permissions screen. Once given or dismissed it says by whom.
    module PackRequest
      def self.build(request)
        blocks = [
          { type: "section", text: { type: "mrkdwn", text: ":key:  *#{Mrkdwn.escape(headline(request))}*" } },
          { type: "divider" },
          { type: "section", text: { type: "mrkdwn", text: Mrkdwn.escape(body(request)) } }
        ]
        settled = settled_line(request)
        return blocks << { type: "context", elements: [ { type: "mrkdwn", text: Mrkdwn.escape(settled) } ] } if settled

        elements = [ { type: "button", text: { type: "plain_text", text: "Give pack" }, action_id: Identifiers::PACK_REQUEST_GIVE,
                       value: request.id, style: "primary" } ]
        url = DashboardUrl.permissions
        elements << { type: "button", text: { type: "plain_text", text: "Open Permissions" }, url: url } if url
        blocks << { type: "actions", elements: elements }
      end

      def self.fallback(request) = headline(request)

      def self.headline(request) = "#{request.requester.display_name} asks for the #{request.role.name} pack"

      def self.body(request)
        "#{request.role.description} They were refused a change that needs it. Giving it covers every environment, " \
          "and you can narrow it on the Permissions screen."
      end

      def self.settled_line(request)
        who = request.given_by&.display_name || "an admin"
        return "Given by #{who}." if request.given_at
        return "Dismissed by #{who}." if request.dismissed_at

        "#{request.requester.display_name} already has it." if request.holds_pack?
      end
    end
  end
end
