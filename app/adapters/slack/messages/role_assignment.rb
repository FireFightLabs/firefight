module Slack
  module Messages
    module RoleAssignment
      UNASSIGNED = "_Unassigned_".freeze

      def self.announcement(changes)
        [
          {
            type: "section",
            text: { type: "mrkdwn", text: ":busts_in_silhouette:  *Incident roles updated*" }
          },
          { type: "divider" },
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
          holder = assigned?(change) ? "assigned" : "cleared"
          "#{change[:role_name]} #{holder}"
        end.join(", ")
      end

      def self.line(change)
        holder = assigned?(change) ? Slack::Mrkdwn.person(change[:platform_user_id], change[:name]) : UNASSIGNED
        "• *#{Slack::Mrkdwn.escape(change[:role_name])}*: #{holder}"
      end
      private_class_method :line

      # A holder with no platform account is still a holder, named by their name.
      def self.assigned?(change)
        change[:platform_user_id].present? || change[:name].present?
      end
      private_class_method :assigned?
    end
  end
end
