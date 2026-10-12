module Integrations
  # A tracker's agent session someone opened, wrote in or asked to stop, taken off the webhook so it answers within the
  # seconds the tracker allows (Integrations::AgentSessions). On the chats' own queue, so the session is told Halon is on
  # it before the tracker marks it unresponsive, never behind an investigation.
  class AgentSessionEventJob < ApplicationJob
    queue_as :conversations

    discard_on ActiveJob::DeserializationError

    def perform(environment_row, event)
      Conversation::IssueSessions.receive!(environment_row, AgentSessions::Event.from_job(event))
    end
  end
end
