# Someone pressed stop on a running investigation.
module Events
  class AgentSessionStoppedHandler
    def self.execute(workspace, payload)
      event = payload["event"]
      investigation = workspace.investigations.live.find_by(thread_id: event["thread_ts"])
      return unless investigation

      investigation.request_cancel!
    end
  end
end
