module FirefightAi
  class IncidentResponseJob < ApplicationJob
    queue_as :default

    discard_on ActiveRecord::RecordNotFound

    def perform(incident_id, channel_id, thread_ts, question, scope_thread_ts = nil)
      incident = Incident.find(incident_id)
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
