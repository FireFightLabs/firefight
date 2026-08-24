class IncidentAiResponseJob < ApplicationJob
  queue_as :default

  retry_on FirefightAi::TransientError, wait: :polynomially_longer, attempts: 3
  discard_on FirefightAi::TerminalError
  discard_on ActiveRecord::RecordNotFound

  def perform(incident_id, channel_id, thread_ts, question, scope_thread_ts = nil)
    incident = Incident.find(incident_id)

    unless Entitlements.allows?(incident.workspace, Entitlements::AI)
      Rails.logger.info({ event: "incident_response.entitlement_blocked", incident_id: incident_id, workspace_id: incident.workspace_id })
      return
    end

    adapter = WorkspaceAdapter.for(incident.workspace)
    answer = FirefightAi::IncidentResponder.new(incident.workspace, output_style: adapter.ai_output_style)
      .answer_question(incident, question: question, scope_thread_ts: scope_thread_ts)

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
