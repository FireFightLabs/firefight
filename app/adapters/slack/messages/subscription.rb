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

      # A DM has no announcement above it, so it gets the incident's name on
      # top and the ways out underneath.
      def self.wrap_update(incident, blocks, workspace:, homepage_url:)
        heading = [
          { type: "section", text: { type: "mrkdwn", text: heading_text(incident) } },
          { type: "divider" }
        ]
        footer = [
          { type: "divider" },
          { type: "actions", elements: footer_buttons(incident, workspace: workspace, homepage_url: homepage_url) }
        ]
        heading + blocks + footer
      end

      def self.heading_text(incident)
        title = ":rotating_light: *#{Slack::Mrkdwn.escape(IncidentDetail.title_for(incident))}*"
        incident.channel_id.present? ? "#{title} in <##{incident.channel_id}>" : title
      end

      def self.footer_buttons(incident, workspace:, homepage_url:)
        buttons = []
        if incident.channel_id.present?
          buttons << {
            type: "button",
            text: { type: "plain_text", text: ":speech_balloon: Open channel", emoji: true },
            url: "https://slack.com/app_redirect?team=#{workspace.platform_id}&channel=#{incident.channel_id}",
            action_id: Identifiers::OPEN_INCIDENT_CHANNEL
          }
        end
        if homepage_url
          buttons << {
            type: "button",
            text: { type: "plain_text", text: ":globe_with_meridians: Incident homepage", emoji: true },
            url: homepage_url,
            action_id: Identifiers::INCIDENT_HOMEPAGE
          }
        end
        buttons << unsubscribe_button(incident)
      end
      private_class_method :footer_buttons

      def self.subscribe_button(incident)
        {
          type: "button",
          text: { type: "plain_text", text: ":bell: Subscribe", emoji: true },
          action_id: Identifiers::SUBSCRIBE_INCIDENT,
          value: incident.id
        }
      end
      private_class_method :subscribe_button

      def self.unsubscribe_button(incident)
        {
          type: "button",
          text: { type: "plain_text", text: ":no_bell: Unsubscribe", emoji: true },
          action_id: Identifiers::UNSUBSCRIBE_INCIDENT,
          value: incident.id
        }
      end
      private_class_method :unsubscribe_button
    end
  end
end
