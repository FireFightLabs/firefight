# Someone pressed stop on a running investigation, or on an answer in a chat thread.
module Events
  class AgentSessionStoppedHandler
    def self.execute(workspace, payload)
      thread_id = payload.dig("event", "thread_ts")
      investigation = workspace.investigations.live.find_by(thread_id: thread_id)
      return investigation.request_cancel! if investigation

      conversation = workspace.conversations.find_by(thread_id: thread_id)
      conversation.request_stop! if conversation && conversation.stop_blocked_reason.nil?
    end
  end
end
