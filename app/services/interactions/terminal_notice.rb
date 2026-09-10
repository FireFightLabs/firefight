module Interactions
  # A Slack client can still show quick actions the incident no longer offers,
  # so a click on one gets an answer rather than silence.
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
