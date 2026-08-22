module Interactions
  # Tells a responder why a button did nothing.
  #
  # The quick actions message drops Escalate and Make me Lead once an incident
  # is over, but a Slack client can still be showing the version that had them.
  # A click on one of those is a real click, so it gets a real answer rather
  # than silence.
  module TerminalNotice
    def self.post(workspace, incident, user_id, reason)
      workspace.adapter.post_ephemeral(
        channel_id: incident.channel_id,
        user_id: user_id,
        text: reason
      )

      nil
    rescue AdapterError => e
      Rails.logger.warn({ event: "interactions.terminal_notice.post_failed", incident_id: incident.id, error: e.message })
      nil
    end
  end
end
