module Slack
  module Messages
    module RoleAssignment
      UNASSIGNED = "_Unassigned_".freeze

      def self.announcement(changes)
        [
          {
            type: "section",
            text: { type: "mrkdwn", text: ":busts_in_silhouette: *Incident roles updated*" }
          },
          {
            type: "section",
            text: { type: "mrkdwn", text: changes.map { |change| line(change) }.join("\n") }
          },
          {
            type: "context",
            elements: [ { type: "mrkdwn", text: "A role names who is accountable. Anyone can still pitch in." } ]
          }
        ]
      end

      def self.summary_text(changes)
        changes.map do |change|
          holder = change[:platform_user_id] ? "assigned" : "cleared"
          "#{change[:role_name]} #{holder}"
        end.join(", ")
      end

      def self.line(change)
        holder = change[:platform_user_id] ? "<@#{change[:platform_user_id]}>" : UNASSIGNED
        "• *#{Slack::Mrkdwn.escape(change[:role_name])}*: #{holder}"
      end
      private_class_method :line
    end
  end
end
