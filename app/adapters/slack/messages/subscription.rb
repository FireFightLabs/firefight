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

      # What a subscriber is sent for each update to an incident: one short card naming the incident, what happened as
      # its subtitle and the words of the update as its body, with Open channel, Open in Firefight and Unsubscribe. The
      # announcement thread's reply itself is never copied, a direct message sits under nothing and is read in one glance.
      def self.digest(incident, headline:, body:, icon:, homepage_url:, rich:)
        WholeCard.build(
          rich: rich, title: Slack::Mrkdwn.escape(IncidentDetail.title_for(incident)), subtitle: headline,
          body: (Formatting.markdown_to_mrkdwn(body) if body.present?), quoted: true,
          actions: digest_buttons(incident, homepage_url: homepage_url), icon: icon
        )
      end

      def self.digest_buttons(incident, homepage_url:)
        buttons = []
        buttons << IncidentDetail.join_channel_button(incident, label: "Open channel") if incident.channel_id.present?
        buttons << IncidentDetail.homepage_button(homepage_url) if homepage_url
        buttons << unsubscribe_button(incident)
      end
      private_class_method :digest_buttons

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
