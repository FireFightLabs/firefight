module FirefightAi
  class IncidentResponseJob < ApplicationJob
    queue_as :default

    discard_on ActiveRecord::RecordNotFound

    def perform(incident_id, channel_id, thread_ts, question, scope_thread_ts = nil)
      incident = Incident.find(incident_id)

      # Execution-time entitlement gate — backstops the enqueue-time check for
      # workspaces whose trial/credits lapse before the job runs.
      unless Entitlements.allows?(incident.workspace, Entitlements::AI)
        Rails.logger.info({ event: "incident_response.entitlement_blocked", incident_id: incident_id, workspace_id: incident.workspace_id })
        return
      end

      answer = IncidentResponder.new(incident.workspace).answer_question(
        incident, question: question, scope_thread_ts: scope_thread_ts
      )
      adapter = incident.workspace.adapter

      if thread_ts
        adapter.post_ai_response_threaded(
          channel_id: channel_id,
          parent_message_id: thread_ts,
          incident: incident,
          answer: answer
        )
      else
        adapter.post_ai_response(channel_id: channel_id, incident: incident, answer: answer)
      end
    end
  end
end
