module Slack
  module Messages
    module Subscription
      # This button is the only place in Slack to change one's own subscription.
      def self.notice(incident, state)
        [
          { type: "section", text: { type: "mrkdwn", text: incident.subscription_notice(state) } },
          { type: "actions", elements: [ state == Incident::Subscriptions::UNSUBSCRIBED ? subscribe_button(incident) : unsubscribe_button(incident) ] }
        ]
      end

      # A direct message has no announcement above it, so a subscriber's copy of a thread reply gets the incident's name
      # and channel on top and the ways out underneath.
      def self.wrap_update(incident, blocks, homepage_url:)
        heading = [ Slack::Blocks.section(heading_text(incident)), { type: "divider" } ]
        footer = [ { type: "divider" }, { type: "actions", elements: footer_buttons(incident, homepage_url: homepage_url) } ]
        heading + blocks + footer
      end

      def self.heading_text(incident)
        title = "#{Slack::Emoji::DECLARED} *#{Slack::Mrkdwn.escape(IncidentDetail.title_for(incident))}*"
        incident.channel_id.present? ? "#{title} in <##{incident.channel_id}>" : title
      end
      private_class_method :heading_text

      def self.footer_buttons(incident, homepage_url:)
        buttons = []
        buttons << IncidentDetail.join_channel_button(incident, label: "Open channel") if incident.channel_id.present?
        buttons << IncidentDetail.homepage_button(homepage_url) if homepage_url
        buttons << unsubscribe_button(incident)
      end
      private_class_method :footer_buttons

      def self.subscribe_button(incident)
        {
          type: "button",
          text: { type: "plain_text", text: "#{Slack::Emoji::SUBSCRIBE} Subscribe", emoji: true },
          action_id: Identifiers::SUBSCRIBE_INCIDENT,
          value: incident.id
        }
      end
      private_class_method :subscribe_button

      def self.unsubscribe_button(incident)
        {
          type: "button",
          text: { type: "plain_text", text: "#{Slack::Emoji::UNSUBSCRIBE} Unsubscribe", emoji: true },
          action_id: Identifiers::UNSUBSCRIBE_INCIDENT,
          value: incident.id
        }
      end
      private_class_method :unsubscribe_button
    end
  end
end
