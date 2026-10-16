module Slack
  module Messages
    # An incident in #incidents, as one card: its title, its state on one line, its summary, and Join channel, Subscribe
    # and Open in Firefight. Who declared it, and custom fields and linked incidents when it has them, follow the card.
    # `build_from` takes a plain hash for the install-time preview, when there is no incident yet.
    module Announcement
      def self.build(incident, rich:)
        card = Slack::Blocks::Card.new(
          title: Mrkdwn.escape(IncidentDetail.title_for(incident)),
          subtitle: IncidentDetail.state_line_for(incident),
          body: body_from(incident.summary), quoted: true,
          actions: [
            (IncidentDetail.join_channel_button(incident) if incident.channel_id.present?),
            IncidentDetail.subscribe_button(incident.id),
            IncidentDetail.homepage_button(Slack::DashboardUrl.incident(incident))
          ].compact,
          icon: Slack::Emoji::DECLARED
        )
        footer = [ IncidentDetail.declared_by_line(incident), (IncidentDetail::TEST_NOTE if incident.is_test?) ].compact
        card.to_blocks(rich: rich) + [ Slack::Blocks.context(footer.join(Formatting::SEPARATOR)) ] + IncidentDetail.extra_blocks(incident)
      end

      def self.build_from(title:, summary:, severity_name:, status_name:, reporter_id:, rich:, homepage_url: nil)
        card = Slack::Blocks::Card.new(
          title: Mrkdwn.escape(title),
          subtitle: IncidentDetail.state_line(severity_name: severity_name, status_name: status_name),
          body: body_from(summary), quoted: true,
          actions: [ IncidentDetail.subscribe_button(nil), IncidentDetail.homepage_button(homepage_url) ],
          icon: Slack::Emoji::DECLARED
        )
        card.to_blocks(rich: rich) + [ Slack::Blocks.context("Declared by #{Mrkdwn.person(reporter_id, nil)}") ]
      end

      def self.body_from(text) = (Formatting.markdown_to_mrkdwn(text) if text.present?)
      private_class_method :body_from
    end
  end
end
