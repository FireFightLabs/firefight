module Interactions
  # Answers a subscribe or unsubscribe click where the person clicked. The
  # click already landed, so a notice that cannot be delivered is logged and
  # never undoes it.
  module SubscriptionNotice
    def self.post(workspace, incident, interaction, state)
      workspace.adapter.post_subscription_notice(
        channel_id: interaction.channel_id,
        user_id: interaction.user_id,
        incident: incident,
        state: state
      )
      nil
    rescue AdapterError => e
      Rails.logger.warn({ event: "interactions.subscription_notice.post_failed", incident_id: incident.id, error: e.message }.to_json)
      nil
    end
  end
end
